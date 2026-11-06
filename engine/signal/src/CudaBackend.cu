/*=========================================================================

  Program:   NutateSignal
  Module:    CudaBackend.cu
  Language:  C++ / CUDA

=========================================================================*/

#include "Execution.h"
#include "CmdInterp.h"
#include "Functions.h"

#include <cuda_runtime.h>
#include <cub/block/block_reduce.cuh>
#include <cub/device/device_for.cuh>
#include <thrust/device_vector.h>
#include <thrust/iterator/counting_iterator.h>
#include <thrust/iterator/transform_iterator.h>

#include <iostream>
#include <vector>
#include <complex>
#include <string>
#include <cmath>
#include <exception>
#include <algorithm>

namespace
{
	// Device storage is split into immutable per-voxel inputs and evolving
	// magnetization pools. The latter mirrors the CPU short/long-T2 and
	// derivative state used by the active z_MODE path.
	struct GpuVec3
	{
		float x, y, z;
	};

	struct GpuComplex
	{
		float real, imag;
	};

	struct GpuComplexDouble
	{
		double real, imag;
	};

	struct GpuRelaxation
	{
		float relaxT2Short;
		float relaxT2Long;
		float relaxZ;
	};

	struct RelaxationKey
	{
		float t1;
		float t2s;
		float t2l;
	};

	struct GpuVoxelStatic
	{
		float posX, posY, posZ;
		float offX, offY, offZ;
		unsigned int relaxIndex;
		float magn0Short;
		float magn0Long;
		float delB0;
		float devDelB0X, devDelB0Y, devDelB0Z;
		float delGradX, delGradY, delGradZ;
	};

	struct GpuMagnetizationPool
	{
		float magnX, magnY, magnZ;
		float dxMagnX, dxMagnY, dxMagnZ;
		float dyMagnX, dyMagnY, dyMagnZ;
		float dzMagnX, dzMagnY, dzMagnZ;
		float dwMagnX, dwMagnY, dwMagnZ;
	};

	struct GpuVoxelDynamic
	{
		GpuMagnetizationPool shortPool;
		GpuMagnetizationPool longPool;
	};

	constexpr unsigned int kCudaBlockSize = 256u;

	template<typename T>
	bool allocateDeviceBuffer(thrust::device_vector<T> & buffer, size_t count, const char * name)
	{
		try
		{
			// Uploads or an explicit memset initialize every element before use.
			buffer = thrust::device_vector<T>(count, thrust::no_init);
			return true;
		}
		catch (const std::exception & error)
		{
			std::cout << "CUDA allocation failed for " << name << ": " << error.what() << std::endl;
			return false;
		}
	}

	template<typename T>
	T * deviceData(thrust::device_vector<T> & buffer)
	{
		return thrust::raw_pointer_cast(buffer.data());
	}

	bool checkCuda(cudaError_t error, const char * context)
	{
		if (error == cudaSuccess)
		{
			return true;
		}

		std::cout << "CUDA error during " << context << ": " << cudaGetErrorString(error) << std::endl;
		return false;
	}

	template<typename T>
	bool copyToDevice(T * ptr, const T * hostPtr, size_t count, const char * context)
	{
		if (count == 0)
		{
			return true;
		}

		return checkCuda(cudaMemcpy(ptr, hostPtr, sizeof(T) * count, cudaMemcpyHostToDevice), context);
	}

	template<typename T>
	bool copyToHost(T * hostPtr, const T * ptr, size_t count, const char * context)
	{
		if (count == 0)
		{
			return true;
		}

		return checkCuda(cudaMemcpy(hostPtr, ptr, sizeof(T) * count, cudaMemcpyDeviceToHost), context);
	}

	bool checkLaunch(const char * context)
	{
		return checkCuda(cudaGetLastError(), context);
	}

	// Sample completed default-stream work without synchronizing every timestep.
	// At most1000 markers are owned; early failure also releases their resources.
	class CudaProgress
	{
	public:
		CudaProgress(ProgressReporter & reporter, unsigned int total)
			: reporter_(reporter), total_(total), next_(0u),
			stride_(std::max(1u, total / 1000u + (total % 1000u != 0u)))
		{
			markers_.reserve(std::min(total, 1000u));
		}
		~CudaProgress()
		{
			for (const Marker & marker : markers_)
				if (marker.event != nullptr) cudaEventDestroy(marker.event);
		}
		bool submitted(unsigned int steps)
		{
			if (steps % stride_ != 0u && steps != total_) return true;
			cudaEvent_t event = nullptr;
			if (!checkCuda(cudaEventCreateWithFlags(&event, cudaEventDisableTiming), "progress event creation")) return false;
			if (!checkCuda(cudaEventRecord(event, 0), "progress event record"))
			{
				cudaEventDestroy(event);
				return false;
			}
			markers_.push_back({event, steps});
			return drain(false);
		}
		bool finish()
		{
			if (!drain(true)) return false;
			reporter_.complete();
			return true;
		}
	private:
		struct Marker { cudaEvent_t event; unsigned int steps; };
		bool drain(bool wait)
		{
			while (next_ < markers_.size())
			{
				Marker & marker = markers_[next_];
				const cudaError_t result = wait ? cudaEventSynchronize(marker.event) : cudaEventQuery(marker.event);
				if (!wait && result == cudaErrorNotReady) return true;
				if (!checkCuda(result, "progress event completion")) return false;
				reporter_.update(marker.steps);
				if (!checkCuda(cudaEventDestroy(marker.event), "progress event release")) return false;
				marker.event = nullptr;
				++next_;
			}
			return true;
		}
		ProgressReporter & reporter_;
		unsigned int total_;
		size_t next_;
		unsigned int stride_;
		std::vector<Marker> markers_;
	};

	bool zeroDeviceMemory(void * ptr, size_t byteCount, const char * context)
	{
		if (byteCount == 0)
		{
			return true;
		}

		return checkCuda(cudaMemset(ptr, 0, byteCount), context);
	}

	__host__ __device__ GpuVec3 makeVec3(float x, float y, float z)
	{
		GpuVec3 value;
		value.x = x;
		value.y = y;
		value.z = z;
		return value;
	}

	__host__ __device__ GpuComplex makeComplex(float real, float imag)
	{
		GpuComplex value;
		value.real = real;
		value.imag = imag;
		return value;
	}

	GpuMagnetizationPool makeMagnetizationPool(float magnX, float magnY, float magnZ)
	{
		GpuMagnetizationPool value = {};
		value.magnX = magnX;
		value.magnY = magnY;
		value.magnZ = magnZ;
		return value;
	}

	__host__ __device__ bool isZeroVec(const GpuVec3 & value)
	{
		return (value.x == 0.0f && value.y == 0.0f && value.z == 0.0f);
	}

	__host__ __device__ float norm3(const GpuVec3 & value)
	{
		return sqrtf(value.x * value.x + value.y * value.y + value.z * value.z);
	}

	__host__ __device__ float sincDevice(float x)
	{
		if (x == 0.0f)
		{
			return 1.0f;
		}

		return sinf(x) / x;
	}

	__host__ __device__ void sincosPair(float x, float & sinValue, float & cosValue)
	{
#ifdef __CUDA_ARCH__
		sincosf(x, &sinValue, &cosValue);
#else
		sinValue = sinf(x);
		cosValue = cosf(x);
#endif
	}

	__host__ __device__ void rotateVec(GpuVec3 & vect, const GpuVec3 & axis, float theta)
	{
		if (!isZeroVec(axis))
		{
			float a;
			float b;
			sincosPair(theta, a, b);

			float x = vect.x;
			float y = vect.y;
			float z = vect.z;

			float u = axis.x;
			float v = axis.y;
			float w = axis.z;

			float temp1 = sqrtf(u*u + v*v + w*w);
			float temp2 = 1.0f / (u*u + v*v + w*w);
			float temp3 = u*x + v*y + w*z;

			vect.x = ( u*temp3 + (x*(v*v+w*w)-u*(v*y+w*z))*b + temp1*(-w*y+v*z)*a ) * temp2;
			vect.y = ( v*temp3 + (y*(u*u+w*w)-v*(u*x+w*z))*b + temp1*( w*x-u*z)*a ) * temp2;
			vect.z = ( w*temp3 + (z*(u*u+v*v)-w*(u*x+v*y))*b + temp1*(-v*x+u*y)*a ) * temp2;
		}
	}

	__host__ __device__ GpuVec3 computeBeff(const GpuVoxelStatic & voxelStatic, const GpuComplex * voxelB1Plus, const GpuComplex * rfStep, unsigned short numTx, float stepBaseZ, const GpuVec3 & grad, const GpuVec3 & wid)
	{
		GpuVec3 beff = makeVec3(0.0f, 0.0f, stepBaseZ);
		double tempReal = 0.0;
		double tempImag = 0.0;

		for (unsigned short int n = 0; n < numTx; n++)
		{
			if (!(rfStep[n].real == 0.0f && rfStep[n].imag == 0.0f))
			{
				const GpuComplex & b1 = voxelB1Plus[n];
				const double prodReal = (double)rfStep[n].real * (double)b1.real - (double)rfStep[n].imag * (double)b1.imag;
				const double prodImag = (double)rfStep[n].real * (double)b1.imag + (double)rfStep[n].imag * (double)b1.real;
				tempReal += prodReal;
				tempImag += prodImag;
			}
		}

		beff.x = (float)tempReal;
		beff.y = (float)tempImag;
		beff.z += (float)(voxelStatic.delB0 +
			wid.x * (voxelStatic.posX + voxelStatic.offX) * (1.0f + voxelStatic.delGradX) * grad.x +
			wid.y * (voxelStatic.posY + voxelStatic.offY) * (1.0f + voxelStatic.delGradY) * grad.y +
			wid.z * (voxelStatic.posZ + voxelStatic.offZ) * (1.0f + voxelStatic.delGradZ) * grad.z);

		return beff;
	}

	__host__ __device__ float computeBeffZ(const GpuVoxelStatic & voxelStatic, float stepBaseZ, const GpuVec3 & grad, const GpuVec3 & wid)
	{
		return (float)(stepBaseZ + voxelStatic.delB0 +
			wid.x * (voxelStatic.posX + voxelStatic.offX) * (1.0f + voxelStatic.delGradX) * grad.x +
			wid.y * (voxelStatic.posY + voxelStatic.offY) * (1.0f + voxelStatic.delGradY) * grad.y +
			wid.z * (voxelStatic.posZ + voxelStatic.offZ) * (1.0f + voxelStatic.delGradZ) * grad.z);
	}

	GpuRelaxation makeRelaxationHost(float durationSeconds, const RelaxationKey & key)
	{
		GpuRelaxation value;
		value.relaxT2Short = (float)std::exp((double)(-durationSeconds / key.t2s));
		value.relaxT2Long = (float)std::exp((double)(-durationSeconds / key.t2l));
		value.relaxZ = (float)std::exp((double)(-durationSeconds / key.t1));
		return value;
	}

	unsigned int findOrAddRelaxationKey(std::vector<RelaxationKey> & keys, float t1, float t2s, float t2l)
	{
		for (unsigned int index = 0; index < (unsigned int)keys.size(); index++)
		{
			if (keys[index].t1 == t1 && keys[index].t2s == t2s && keys[index].t2l == t2l)
			{
				return index;
			}
		}

		RelaxationKey key;
		key.t1 = t1;
		key.t2s = t2s;
		key.t2l = t2l;
		keys.push_back(key);
		return (unsigned int)keys.size() - 1u;
	}

	__host__ __device__ void updateDMagnPoolState(const GpuVoxelStatic & voxelStatic, GpuMagnetizationPool & pool, const GpuVec3 & grad, const GpuVec3 & beff, float durationSeconds, float relaxXY, float relaxZ, float gammaRadPerTPerS)
	{
		const float thetaRF = gammaRadPerTPerS * durationSeconds * sqrtf(beff.x * beff.x + beff.y * beff.y);
		const float thetaZ = -gammaRadPerTPerS * durationSeconds * beff.z;
		float sinThetaZ;
		float cosThetaZ;
		sincosPair(thetaZ, sinThetaZ, cosThetaZ);
		const float rotatedMagnX = -sinThetaZ * pool.magnX + cosThetaZ * pool.magnY;
		const float rotatedMagnY = -cosThetaZ * pool.magnX - sinThetaZ * pool.magnY;
		const float gradTermX = durationSeconds * gammaRadPerTPerS * (grad.x * (1.0f + voxelStatic.delGradX) + voxelStatic.devDelB0X);
		const float gradTermY = durationSeconds * gammaRadPerTPerS * (grad.y * (1.0f + voxelStatic.delGradY) + voxelStatic.devDelB0Y);
		const float gradTermZ = durationSeconds * gammaRadPerTPerS * (grad.z * (1.0f + voxelStatic.delGradZ) + voxelStatic.devDelB0Z);
		const GpuVec3 tempBeffTrans = makeVec3(beff.x, beff.y, 0.0f);

		GpuVec3 tempDxMagn = makeVec3(gradTermX * rotatedMagnX + cosThetaZ * pool.dxMagnX + sinThetaZ * pool.dxMagnY,
			gradTermX * rotatedMagnY - sinThetaZ * pool.dxMagnX + cosThetaZ * pool.dxMagnY,
			pool.dxMagnZ);
		rotateVec(tempDxMagn, tempBeffTrans, thetaRF);
		tempDxMagn.x *= relaxXY;
		tempDxMagn.y *= relaxXY;
		tempDxMagn.z *= relaxZ;

		GpuVec3 tempDyMagn = makeVec3(gradTermY * rotatedMagnX + cosThetaZ * pool.dyMagnX + sinThetaZ * pool.dyMagnY,
			gradTermY * rotatedMagnY - sinThetaZ * pool.dyMagnX + cosThetaZ * pool.dyMagnY,
			pool.dyMagnZ);
		rotateVec(tempDyMagn, tempBeffTrans, thetaRF);
		tempDyMagn.x *= relaxXY;
		tempDyMagn.y *= relaxXY;
		tempDyMagn.z *= relaxZ;

		GpuVec3 tempDzMagn = makeVec3(gradTermZ * rotatedMagnX + cosThetaZ * pool.dzMagnX + sinThetaZ * pool.dzMagnY,
			gradTermZ * rotatedMagnY - sinThetaZ * pool.dzMagnX + cosThetaZ * pool.dzMagnY,
			pool.dzMagnZ);
		rotateVec(tempDzMagn, tempBeffTrans, thetaRF);
		tempDzMagn.x *= relaxXY;
		tempDzMagn.y *= relaxXY;
		tempDzMagn.z *= relaxZ;

		GpuVec3 tempDwMagn = makeVec3(durationSeconds * rotatedMagnX + cosThetaZ * pool.dwMagnX + sinThetaZ * pool.dwMagnY,
			durationSeconds * rotatedMagnY - sinThetaZ * pool.dwMagnX + cosThetaZ * pool.dwMagnY,
			pool.dwMagnZ);
		rotateVec(tempDwMagn, tempBeffTrans, thetaRF);
		tempDwMagn.x *= relaxXY;
		tempDwMagn.y *= relaxXY;
		tempDwMagn.z *= relaxZ;

		pool.dxMagnX = tempDxMagn.x;
		pool.dxMagnY = tempDxMagn.y;
		pool.dxMagnZ = tempDxMagn.z;
		pool.dyMagnX = tempDyMagn.x;
		pool.dyMagnY = tempDyMagn.y;
		pool.dyMagnZ = tempDyMagn.z;
		pool.dzMagnX = tempDzMagn.x;
		pool.dzMagnY = tempDzMagn.y;
		pool.dzMagnZ = tempDzMagn.z;
		pool.dwMagnX = tempDwMagn.x;
		pool.dwMagnY = tempDwMagn.y;
		pool.dwMagnZ = tempDwMagn.z;
	}

	__host__ __device__ void updateDMagnState(const GpuVoxelStatic & voxelStatic, GpuVoxelDynamic & voxelDynamic, const GpuVec3 & grad, const GpuVec3 & beff, float durationSeconds, const GpuRelaxation & relaxation, float gammaRadPerTPerS)
	{
		updateDMagnPoolState(voxelStatic, voxelDynamic.shortPool, grad, beff, durationSeconds, relaxation.relaxT2Short, relaxation.relaxZ, gammaRadPerTPerS);
		if (voxelStatic.magn0Long != 0.0f)
		{
			updateDMagnPoolState(voxelStatic, voxelDynamic.longPool, grad, beff, durationSeconds, relaxation.relaxT2Long, relaxation.relaxZ, gammaRadPerTPerS);
		}
	}

	__host__ __device__ void updateDMagnPoolStateZOnly(const GpuVoxelStatic & voxelStatic, GpuMagnetizationPool & pool, const GpuVec3 & grad, float beffZ, float durationSeconds, float relaxXY, float relaxZ, float gammaRadPerTPerS)
	{
		const float thetaZ = -gammaRadPerTPerS * durationSeconds * beffZ;
		float sinThetaZ;
		float cosThetaZ;
		sincosPair(thetaZ, sinThetaZ, cosThetaZ);
		const float rotatedMagnX = -sinThetaZ * pool.magnX + cosThetaZ * pool.magnY;
		const float rotatedMagnY = -cosThetaZ * pool.magnX - sinThetaZ * pool.magnY;
		const float gradTermX = durationSeconds * gammaRadPerTPerS * (grad.x * (1.0f + voxelStatic.delGradX) + voxelStatic.devDelB0X);
		const float gradTermY = durationSeconds * gammaRadPerTPerS * (grad.y * (1.0f + voxelStatic.delGradY) + voxelStatic.devDelB0Y);
		const float gradTermZ = durationSeconds * gammaRadPerTPerS * (grad.z * (1.0f + voxelStatic.delGradZ) + voxelStatic.devDelB0Z);

		const float dxMagnX = pool.dxMagnX;
		const float dxMagnY = pool.dxMagnY;
		const float dyMagnX = pool.dyMagnX;
		const float dyMagnY = pool.dyMagnY;
		const float dzMagnX = pool.dzMagnX;
		const float dzMagnY = pool.dzMagnY;
		const float dwMagnX = pool.dwMagnX;
		const float dwMagnY = pool.dwMagnY;

		pool.dxMagnX = (gradTermX * rotatedMagnX + cosThetaZ * dxMagnX + sinThetaZ * dxMagnY) * relaxXY;
		pool.dxMagnY = (gradTermX * rotatedMagnY - sinThetaZ * dxMagnX + cosThetaZ * dxMagnY) * relaxXY;
		pool.dxMagnZ *= relaxZ;

		pool.dyMagnX = (gradTermY * rotatedMagnX + cosThetaZ * dyMagnX + sinThetaZ * dyMagnY) * relaxXY;
		pool.dyMagnY = (gradTermY * rotatedMagnY - sinThetaZ * dyMagnX + cosThetaZ * dyMagnY) * relaxXY;
		pool.dyMagnZ *= relaxZ;

		pool.dzMagnX = (gradTermZ * rotatedMagnX + cosThetaZ * dzMagnX + sinThetaZ * dzMagnY) * relaxXY;
		pool.dzMagnY = (gradTermZ * rotatedMagnY - sinThetaZ * dzMagnX + cosThetaZ * dzMagnY) * relaxXY;
		pool.dzMagnZ *= relaxZ;

		pool.dwMagnX = (durationSeconds * rotatedMagnX + cosThetaZ * dwMagnX + sinThetaZ * dwMagnY) * relaxXY;
		pool.dwMagnY = (durationSeconds * rotatedMagnY - sinThetaZ * dwMagnX + cosThetaZ * dwMagnY) * relaxXY;
		pool.dwMagnZ *= relaxZ;
	}

	__host__ __device__ void updateDMagnStateZOnly(const GpuVoxelStatic & voxelStatic, GpuVoxelDynamic & voxelDynamic, const GpuVec3 & grad, float beffZ, float durationSeconds, const GpuRelaxation & relaxation, float gammaRadPerTPerS)
	{
		updateDMagnPoolStateZOnly(voxelStatic, voxelDynamic.shortPool, grad, beffZ, durationSeconds, relaxation.relaxT2Short, relaxation.relaxZ, gammaRadPerTPerS);
		if (voxelStatic.magn0Long != 0.0f)
		{
			updateDMagnPoolStateZOnly(voxelStatic, voxelDynamic.longPool, grad, beffZ, durationSeconds, relaxation.relaxT2Long, relaxation.relaxZ, gammaRadPerTPerS);
		}
	}

	__host__ __device__ void applyRotationAndRelaxationPool(GpuMagnetizationPool & pool, const GpuVec3 & beff, float relaxXY, float relaxZ, float magn0, float durationSeconds, float gammaRadPerTPerS)
	{
		if (!isZeroVec(beff))
		{
			const float theta = gammaRadPerTPerS * durationSeconds * norm3(beff);
			GpuVec3 magn = makeVec3(pool.magnX, pool.magnY, pool.magnZ);
			rotateVec(magn, beff, theta);
			pool.magnX = magn.x;
			pool.magnY = magn.y;
			pool.magnZ = magn.z;
		}

		pool.magnX *= relaxXY;
		pool.magnY *= relaxXY;
		pool.magnZ = magn0 - (magn0 - pool.magnZ) * relaxZ;
	}

	__host__ __device__ void applyRotationAndRelaxation(const GpuVoxelStatic & voxelStatic, GpuVoxelDynamic & voxelDynamic, const GpuVec3 & beff, const GpuRelaxation & relaxation, float durationSeconds, float gammaRadPerTPerS)
	{
		applyRotationAndRelaxationPool(voxelDynamic.shortPool, beff, relaxation.relaxT2Short, relaxation.relaxZ, voxelStatic.magn0Short, durationSeconds, gammaRadPerTPerS);
		if (voxelStatic.magn0Long != 0.0f)
		{
			applyRotationAndRelaxationPool(voxelDynamic.longPool, beff, relaxation.relaxT2Long, relaxation.relaxZ, voxelStatic.magn0Long, durationSeconds, gammaRadPerTPerS);
		}
	}

	__host__ __device__ void applyRotationAndRelaxationPoolZOnly(GpuMagnetizationPool & pool, float beffZ, float relaxXY, float relaxZ, float magn0, float durationSeconds, float gammaRadPerTPerS)
	{
		const float theta = gammaRadPerTPerS * durationSeconds * beffZ;
		float sinTheta;
		float cosTheta;
		sincosPair(theta, sinTheta, cosTheta);
		const float magnX = pool.magnX;
		const float magnY = pool.magnY;

		pool.magnX = (magnX * cosTheta - magnY * sinTheta) * relaxXY;
		pool.magnY = (magnX * sinTheta + magnY * cosTheta) * relaxXY;
		pool.magnZ = magn0 - (magn0 - pool.magnZ) * relaxZ;
	}

	__host__ __device__ void applyRotationAndRelaxationZOnly(const GpuVoxelStatic & voxelStatic, GpuVoxelDynamic & voxelDynamic, float beffZ, const GpuRelaxation & relaxation, float durationSeconds, float gammaRadPerTPerS)
	{
		applyRotationAndRelaxationPoolZOnly(voxelDynamic.shortPool, beffZ, relaxation.relaxT2Short, relaxation.relaxZ, voxelStatic.magn0Short, durationSeconds, gammaRadPerTPerS);
		if (voxelStatic.magn0Long != 0.0f)
		{
			applyRotationAndRelaxationPoolZOnly(voxelDynamic.longPool, beffZ, relaxation.relaxT2Long, relaxation.relaxZ, voxelStatic.magn0Long, durationSeconds, gammaRadPerTPerS);
		}
	}

	__device__ void loadRfStepShared(GpuComplex * sharedRfStep, const GpuComplex * rfStep, unsigned short numTx)
	{
		for (unsigned int tx = threadIdx.x; tx < (unsigned int)numTx; tx += blockDim.x)
		{
			sharedRfStep[tx] = rfStep[tx];
		}
	}

	__device__ void evolveMagnetizationRFOn(const GpuVoxelStatic & voxelStatic, GpuVoxelDynamic & voxelDynamic, const GpuComplex * voxelB1Plus, const GpuComplex * rfStep, const GpuRelaxation * relaxationStep, unsigned short numTx, float stepBaseZ, const GpuVec3 & grad, const GpuVec3 & wid, float durationSeconds, float gammaRadPerTPerS)
	{
		// Match Voxel::evolveMagnetization: derivatives first, then rotation/relaxation.
		const GpuVec3 beff = computeBeff(voxelStatic, voxelB1Plus, rfStep, numTx, stepBaseZ, grad, wid);
		const GpuRelaxation relaxation = relaxationStep[voxelStatic.relaxIndex];
		updateDMagnState(voxelStatic, voxelDynamic, grad, beff, durationSeconds, relaxation, gammaRadPerTPerS);
		applyRotationAndRelaxation(voxelStatic, voxelDynamic, beff, relaxation, durationSeconds, gammaRadPerTPerS);
	}

	__device__ void evolveMagnetizationRFOff(const GpuVoxelStatic & voxelStatic, GpuVoxelDynamic & voxelDynamic, const GpuRelaxation * relaxationStep, float stepBaseZ, const GpuVec3 & grad, const GpuVec3 & wid, float durationSeconds, float gammaRadPerTPerS)
	{
		// The RF-off path retains the same physical order with longitudinal-field formulas.
		const float beffZ = computeBeffZ(voxelStatic, stepBaseZ, grad, wid);
		const GpuRelaxation relaxation = relaxationStep[voxelStatic.relaxIndex];
		updateDMagnStateZOnly(voxelStatic, voxelDynamic, grad, beffZ, durationSeconds, relaxation, gammaRadPerTPerS);
		applyRotationAndRelaxationZOnly(voxelStatic, voxelDynamic, beffZ, relaxation, durationSeconds, gammaRadPerTPerS);
	}

	__global__ void applyStepKernel(const GpuVoxelStatic * voxelStatic, GpuVoxelDynamic * voxelDynamic, const GpuComplex * b1Plus, const GpuComplex * rfStep, const GpuRelaxation * relaxationStep, unsigned int voxelCount, unsigned short numTx, float stepBaseZ, GpuVec3 grad, GpuVec3 wid, float durationSeconds, float gammaRadPerTPerS)
	{
		extern __shared__ GpuComplex sharedRfStep[];
		loadRfStepShared(sharedRfStep, rfStep, numTx);
		__syncthreads();

		unsigned int index = blockIdx.x * blockDim.x + threadIdx.x;
		if (index >= voxelCount)
		{
			return;
		}

		GpuVoxelDynamic localDynamic = voxelDynamic[index];
		const GpuVoxelStatic localStatic = voxelStatic[index];
		const GpuComplex * voxelB1Plus = b1Plus + ((size_t)index * (size_t)numTx);
		evolveMagnetizationRFOn(localStatic, localDynamic, voxelB1Plus, sharedRfStep, relaxationStep, numTx, stepBaseZ, grad, wid, durationSeconds, gammaRadPerTPerS);

		voxelDynamic[index] = localDynamic;
	}

	__global__ void applyStepOffKernel(const GpuVoxelStatic * voxelStatic, GpuVoxelDynamic * voxelDynamic, const GpuRelaxation * relaxationStep, unsigned int voxelCount, float stepBaseZ, GpuVec3 grad, GpuVec3 wid, float durationSeconds, float gammaRadPerTPerS)
	{
		unsigned int index = blockIdx.x * blockDim.x + threadIdx.x;
		if (index >= voxelCount)
		{
			return;
		}

		GpuVoxelDynamic localDynamic = voxelDynamic[index];
		const GpuVoxelStatic localStatic = voxelStatic[index];
		evolveMagnetizationRFOff(localStatic, localDynamic, relaxationStep, stepBaseZ, grad, wid, durationSeconds, gammaRadPerTPerS);

		voxelDynamic[index] = localDynamic;
	}

	// The active CUDA signal path matches the CPU z_MODE and only needs the x/y phase derivatives.
	__host__ __device__ void computeSignalPhaseXY(const GpuVoxelDynamic & value, float & dxPhi, float & dyPhi)
	{
		const float magnX = value.shortPool.magnX + value.longPool.magnX;
		const float magnY = value.shortPool.magnY + value.longPool.magnY;
		if (magnX == 0.0f && magnY == 0.0f)
		{
			dxPhi = 0.0f;
			dyPhi = 0.0f;
		}
		else
		{
			const float dxMagnX = value.shortPool.dxMagnX + value.longPool.dxMagnX;
			const float dxMagnY = value.shortPool.dxMagnY + value.longPool.dxMagnY;
			const float dyMagnX = value.shortPool.dyMagnX + value.longPool.dyMagnX;
			const float dyMagnY = value.shortPool.dyMagnY + value.longPool.dyMagnY;
			const float transNorm2 = magnX * magnX + magnY * magnY;
			dxPhi = (magnX * dxMagnY - magnY * dxMagnX) / transNorm2;
			dyPhi = (magnX * dyMagnY - magnY * dyMagnX) / transNorm2;
		}
	}

	// Named step parameters keep launch sites auditable and prevent positional
	// mix-ups between time, field, phase and signal scaling values.
	// Field inputs are tesla and T/m; widths metres; durations seconds.
	struct AcquisitionStep
	{
		GpuVec3 gradient;
		GpuVec3 voxelWidth;
		float baseFieldZ;
		// Split at the original ADC observation within the current field interval.
		float timeToSampleSeconds, timeAfterSampleSeconds;
		float phaseScaleX, phaseScaleY;
		float voxelVolume;
		float b0;
		float gammaRadPerTPerS;
		unsigned int sampleIndex;
	};

	struct MidpointSignal
	{
		double magnX, magnY;
		double scale;
	};

	__device__ MidpointSignal computeMidpointSignal(
		const GpuVoxelStatic & voxel, const GpuVoxelDynamic & state,
		const AcquisitionStep & step)
	{
		float dxPhi, dyPhi;
		computeSignalPhaseXY(state, dxPhi, dyPhi);
		const double phaseX = (double)sincDevice(step.phaseScaleX * dxPhi);
		const double phaseY = (double)sincDevice(step.phaseScaleY * dyPhi);
		MidpointSignal signal;
		signal.scale = (double)step.gammaRadPerTPerS * (double)(step.b0 + voxel.delB0) *
			(double)step.voxelVolume * phaseX * phaseY;
		signal.magnX = (double)(state.shortPool.magnX + state.longPool.magnX);
		signal.magnY = (double)(state.shortPool.magnY + state.longPool.magnY);
		return signal;
	}

	// Small receiver tiles amortize collective synchronization without keeping
	// four or eight receivers' reduction intermediates live in every thread.
	template<unsigned int ReceiverTileSize>
	struct SignalTile
	{
		double real[ReceiverTileSize];
		double imag[ReceiverTileSize];
	};

	template<unsigned int ReceiverTileSize>
	struct AddSignalTile
	{
		__device__ SignalTile<ReceiverTileSize> operator()(
			const SignalTile<ReceiverTileSize> & a,
			const SignalTile<ReceiverTileSize> & b) const
		{
			SignalTile<ReceiverTileSize> sum;
			#pragma unroll
			for (unsigned int receiver = 0; receiver < ReceiverTileSize; receiver++)
			{
				sum.real[receiver] = a.real[receiver] + b.real[receiver];
				sum.imag[receiver] = a.imag[receiver] + b.imag[receiver];
			}
			return sum;
		}
	};

	template<bool RfActive>
	__device__ void evolveAcquisitionPart(
		const GpuVoxelStatic & voxel, GpuVoxelDynamic & state,
		const GpuComplex * voxelB1Plus, const GpuComplex * rfStep,
		const GpuRelaxation * relaxationStep, unsigned short numTx,
		const AcquisitionStep & step, float duration)
	{
		if (duration == 0.0f) return;
		if constexpr (RfActive)
		{
			evolveMagnetizationRFOn(voxel, state, voxelB1Plus, rfStep, relaxationStep,
				numTx, step.baseFieldZ, step.gradient, step.voxelWidth,
				duration, step.gammaRadPerTPerS);
		}
		else
		{
			evolveMagnetizationRFOff(voxel, state, relaxationStep, step.baseFieldZ,
				step.gradient, step.voxelWidth, duration, step.gammaRadPerTPerS);
		}
	}

	template<bool RfActive, unsigned int ReceiverTileSize>
	__global__ __launch_bounds__(kCudaBlockSize, RfActive ? 2 : 3)
	void applyAcquisitionSignalKernel(
		const GpuVoxelStatic * voxelStatic, GpuVoxelDynamic * voxelDynamic,
		const GpuComplex * b1Plus, const GpuComplex * b1Mins,
		const GpuComplex * rfStep, const GpuRelaxation * relaxationBefore,
		const GpuRelaxation * relaxationAfter,
		unsigned int voxelCount, unsigned short numTx, unsigned short numRx,
		AcquisitionStep step, GpuComplexDouble * kSpaceSignal)
	{
		// Raking limits double-component shuffle work. Launch bounds cap register
		// use to leave room for three RF-off or two RF-on blocks per register file.
		using BlockReduce = cub::BlockReduce<SignalTile<ReceiverTileSize>,
			kCudaBlockSize, cub::BLOCK_REDUCE_RAKING_COMMUTATIVE_ONLY>;
		__shared__ typename BlockReduce::TempStorage reductionStorage;
		extern __shared__ GpuComplex sharedRfStep[];
		if constexpr (RfActive)
		{
			loadRfStepShared(sharedRfStep, rfStep, numTx);
			__syncthreads();
		}

		const unsigned int voxelIndex = blockIdx.x * blockDim.x + threadIdx.x;
		const bool active = voxelIndex < voxelCount;
		GpuVoxelDynamic localDynamic;
		GpuVoxelStatic localStatic;
		const GpuComplex * voxelB1Plus = NULL;
		MidpointSignal midpoint = {};

		// Evolve to the original ADC observation and reuse its state for all receivers.
		if (active)
		{
			localDynamic = voxelDynamic[voxelIndex];
			localStatic = voxelStatic[voxelIndex];
			if constexpr (RfActive)
			{
				voxelB1Plus = b1Plus + ((size_t)voxelIndex * (size_t)numTx);
			}
			evolveAcquisitionPart<RfActive>(localStatic, localDynamic,
				voxelB1Plus, sharedRfStep, relaxationBefore, numTx, step, step.timeToSampleSeconds);
			midpoint = computeMidpointSignal(localStatic, localDynamic, step);
		}

		const size_t sampleBase = (size_t)step.sampleIndex * (size_t)numRx;
		for (unsigned int coilBase = 0; coilBase < (unsigned int)numRx;
			coilBase += ReceiverTileSize)
		{
			SignalTile<ReceiverTileSize> contribution = {};
			if (active)
			{
				#pragma unroll
				for (unsigned int receiver = 0; receiver < ReceiverTileSize; receiver++)
				{
					const unsigned int coilIndex = coilBase + receiver;
					if (coilIndex < (unsigned int)numRx)
					{
						const GpuComplex & sensitivity =
							b1Mins[(size_t)coilIndex * (size_t)voxelCount + voxelIndex];
						const double conjReal = (double)sensitivity.real;
						const double conjImag = (double)(-sensitivity.imag);
						contribution.real[receiver] =
							(midpoint.magnX * conjReal - midpoint.magnY * conjImag) * midpoint.scale;
						contribution.imag[receiver] =
							(midpoint.magnX * conjImag + midpoint.magnY * conjReal) * midpoint.scale;
					}
				}
			}

			// Every thread participates, including zero-padded voxels/receivers.
			// The CUB tree changes rounding order; cross-block double atomics remain.
			const SignalTile<ReceiverTileSize> sum = BlockReduce(reductionStorage).
				Reduce(contribution, AddSignalTile<ReceiverTileSize>());
			if (threadIdx.x == 0)
			{
				#pragma unroll
				for (unsigned int receiver = 0; receiver < ReceiverTileSize; receiver++)
				{
					const unsigned int coilIndex = coilBase + receiver;
					if (coilIndex < (unsigned int)numRx)
					{
						atomicAdd(&kSpaceSignal[sampleBase + coilIndex].real, sum.real[receiver]);
						atomicAdd(&kSpaceSignal[sampleBase + coilIndex].imag, sum.imag[receiver]);
					}
				}
			}
			__syncthreads(); // Protect CUB temporary storage before the next tile.
		}

		// Evolve the remainder and commit voxel state once, after all receivers.
		if (active)
		{
			evolveAcquisitionPart<RfActive>(localStatic, localDynamic,
				voxelB1Plus, sharedRfStep, relaxationAfter, numTx, step, step.timeAfterSampleSeconds);
			voxelDynamic[voxelIndex] = localDynamic;
		}
	}

	template<bool RfActive>
	bool launchAcquisitionSignalKernel(
		const GpuVoxelStatic * voxelStatic, GpuVoxelDynamic * voxelDynamic,
		const GpuComplex * b1Plus, const GpuComplex * b1Mins,
		const GpuComplex * rfStep, const GpuRelaxation * relaxationBefore,
		const GpuRelaxation * relaxationAfter,
		unsigned int voxelCount, unsigned short numTx, unsigned short numRx,
		const AcquisitionStep & step, GpuComplexDouble * kSpaceSignal)
	{
		const unsigned int blocks = (voxelCount + kCudaBlockSize - 1u) / kCudaBlockSize;
		const size_t rfSharedBytes = RfActive ? (size_t)numTx * sizeof(GpuComplex) : 0;
		if (numRx == 1)
		{
			applyAcquisitionSignalKernel<RfActive, 1><<<blocks, kCudaBlockSize, rfSharedBytes>>>(
				voxelStatic, voxelDynamic, b1Plus, b1Mins, rfStep, relaxationBefore, relaxationAfter,
				voxelCount, numTx, numRx, step, kSpaceSignal);
		}
		else
		{
			applyAcquisitionSignalKernel<RfActive, 2><<<blocks, kCudaBlockSize, rfSharedBytes>>>(
				voxelStatic, voxelDynamic, b1Plus, b1Mins, rfStep, relaxationBefore, relaxationAfter,
				voxelCount, numTx, numRx, step, kSpaceSignal);
		}
		return checkLaunch(RfActive ? "fused acquisition kernel launch" :
			"fused RF-off acquisition kernel launch");
	}

	struct CrushPool
	{
		__device__ void operator()(GpuMagnetizationPool & pool) const
		{
			pool.magnX = 0.0f;
			pool.magnY = 0.0f;
			pool.dxMagnX = 0.0f;
			pool.dxMagnY = 0.0f;
			pool.dxMagnZ = 0.0f;
			pool.dyMagnX = 0.0f;
			pool.dyMagnY = 0.0f;
			pool.dyMagnZ = 0.0f;
			pool.dzMagnX = 0.0f;
			pool.dzMagnY = 0.0f;
			pool.dzMagnZ = 0.0f;
			pool.dwMagnX = 0.0f;
			pool.dwMagnY = 0.0f;
			pool.dwMagnZ = 0.0f;
		}
	};

	// Expose the short/long pools in voxel order as references to existing state.
	struct VoxelPoolAt
	{
		GpuVoxelDynamic * voxels;
		__device__ GpuMagnetizationPool & operator()(size_t poolIndex) const
		{
			GpuVoxelDynamic & voxel = voxels[poolIndex / 2];
			return poolIndex % 2 == 0 ? voxel.shortPool : voxel.longPool;
		}
	};

	bool applyCrusher(GpuVoxelDynamic * voxelDynamic, unsigned int voxelCount)
	{
		// Smaller pool items keep CCCL's work distribution efficient. The iterator
		// is a view: state layout, storage and longitudinal values stay the same.
		const auto pools = thrust::make_transform_iterator(
			thrust::make_counting_iterator(size_t(0)), VoxelPoolAt{voxelDynamic});
		return checkCuda(cub::DeviceFor::ForEachN(pools, size_t(voxelCount) * 2,
			CrushPool{}), "crusher operation");
	}

	class CudaSimulationState
	{
	public:
		CudaSimulationState()
			: voxelCount(0), numTx(0), numRx(0), b0(0.0f), gammaHzPerT(0.0f), gammaRadPerTPerS(0.0f), wid(makeVec3(0.0f, 0.0f, 0.0f)), signalPhaseScaleX(0.0f), signalPhaseScaleY(0.0f), signalVoxelVolume(0.0f),
			  relaxTypeCount(0), rfSharedBytes(0), deviceIndex(0)
		{
		}

		bool initialize(Execution & run, unsigned int acquisitionCount)
		{
			int deviceCount = 0;
			if (!checkCuda(cudaGetDeviceCount(&deviceCount), "cudaGetDeviceCount"))
			{
				return false;
			}
			if (deviceCount <= 0)
			{
				std::cout << "No CUDA devices are available." << std::endl;
				return false;
			}

			int bestDevice = 0;
			int bestScore = -1;
			cudaDeviceProp bestProps;
			for (int candidateIndex = 0; candidateIndex < deviceCount; candidateIndex++)
			{
				cudaDeviceProp props;
				if (!checkCuda(cudaGetDeviceProperties(&props, candidateIndex), "cudaGetDeviceProperties"))
				{
					return false;
				}

				const int score = props.multiProcessorCount;
				if (score > bestScore)
				{
					bestScore = score;
					bestDevice = candidateIndex;
					bestProps = props;
				}
			}

			this->deviceIndex = bestDevice;
			deviceName = bestProps.name;

			if (!checkCuda(cudaSetDevice(this->deviceIndex), "cudaSetDevice"))
			{
				return false;
			}

			Execution::Info & info = run.getInfo();
			std::vector<Voxel> & phantom = run.getPhantom();
			Execution::Sequence & sequence = run.getSequence();

			voxelCount = (unsigned int)phantom.size();
			numTx = info.numTx;
			numRx = info.numRx;
			b0 = info.b0;
			gammaHzPerT = info.nucleus.gammaHzPerT;
			gammaRadPerTPerS = info.nucleus.gammaRadPerTPerS;
			const float delFreqScale = (numTx == 0) ? 0.0f : -(1.0f / (float)numTx) / gammaHzPerT;
			wid = makeVec3(info.wid.x, info.wid.y, info.wid.z);
			signalPhaseScaleX = ((float)info.numIso.x == 0.0f) ? 0.0f : (info.wid.x / (float)info.numIso.x) * 0.5f;
			signalPhaseScaleY = ((float)info.numIso.y == 0.0f) ? 0.0f : (info.wid.y / (float)info.numIso.y) * 0.5f;
			signalVoxelVolume = ((float)info.numIso.x == 0.0f || (float)info.numIso.y == 0.0f || (float)info.numIso.z == 0.0f) ? 0.0f :
				(info.wid.x / (float)info.numIso.x) * (info.wid.y / (float)info.numIso.y) * (info.wid.z / (float)info.numIso.z);
			rfSharedBytes = (size_t)numTx * sizeof(GpuComplex);
			const size_t sequenceEntryCount = (size_t)numTx * (size_t)sequence.time.size();

			const unsigned int isoCount = (unsigned int)info.numIso.x * (unsigned int)info.numIso.y * (unsigned int)info.numIso.z;
			std::vector<RelaxationKey> relaxationKeys;
			std::vector<unsigned int> relaxationIndexHost(voxelCount);
			for (unsigned int i = 0; i < voxelCount; i++)
			{
				relaxationIndexHost[i] = findOrAddRelaxationKey(relaxationKeys, phantom[i].tissInfo.t1, phantom[i].tissInfo.t2s, phantom[i].tissInfo.t2l);
			}
			relaxTypeCount = (unsigned int)relaxationKeys.size();
			const size_t relaxationEntryCount = (size_t)sequence.time.size() * (size_t)relaxTypeCount;

			std::vector<GpuVoxelStatic> voxelStaticHost(voxelCount);
			std::vector<GpuVoxelDynamic> voxelDynamicHost(voxelCount);
			std::vector<GpuComplex> b1PlusHost((size_t)voxelCount * (size_t)numTx);
			std::vector<GpuComplex> b1MinsHost((size_t)voxelCount * (size_t)numRx);
			std::vector<GpuComplex> rfSequenceHost(sequenceEntryCount);
			std::vector<GpuRelaxation> relaxationFullHost(relaxationEntryCount);
			std::vector<GpuRelaxation> relaxationBeforeHost(relaxationEntryCount);
			std::vector<GpuRelaxation> relaxationAfterHost(relaxationEntryCount);
			stepBaseZHost.resize(sequence.time.size());
			rfActiveHost.resize(sequence.time.size());

			if (!allocateDeviceBuffer(voxelStatic, voxelCount, "voxelStatic") ||
				!allocateDeviceBuffer(voxelDynamic, voxelCount, "voxelDynamic") ||
				!allocateDeviceBuffer(b1Plus, (size_t)voxelCount * (size_t)numTx, "b1Plus") ||
				!allocateDeviceBuffer(b1Mins, (size_t)voxelCount * (size_t)numRx, "b1Mins") ||
				!allocateDeviceBuffer(rfStep, sequenceEntryCount, "rfStep") ||
				!allocateDeviceBuffer(relaxationFull, relaxationEntryCount, "relaxationFull") ||
				!allocateDeviceBuffer(relaxationBefore, relaxationEntryCount, "relaxationBefore") ||
				!allocateDeviceBuffer(relaxationAfter, relaxationEntryCount, "relaxationAfter") ||
				!allocateDeviceBuffer(kSpaceSignal, (size_t)acquisitionCount * (size_t)numRx, "kSpaceSignal"))
			{
				return false;
			}

			kSpaceSignalHost.resize((size_t)acquisitionCount * (size_t)numRx);
			if (!zeroDeviceMemory(deviceData(kSpaceSignal), sizeof(GpuComplexDouble) * kSpaceSignal.size(), "kSpaceSignal clear"))
			{
				return false;
			}

			for (unsigned int i = 0; i < voxelCount; i++)
			{
				const unsigned int offsetIndex = (isoCount == 0) ? 0 : (i % isoCount);
				const Vect3D<float> magn = phantom[i].getMagn();

				voxelStaticHost[i].posX = phantom[i].geomInfo.pos.x;
				voxelStaticHost[i].posY = phantom[i].geomInfo.pos.y;
				voxelStaticHost[i].posZ = phantom[i].geomInfo.pos.z;
				voxelStaticHost[i].offX = info.offSet[offsetIndex].x;
				voxelStaticHost[i].offY = info.offSet[offsetIndex].y;
				voxelStaticHost[i].offZ = info.offSet[offsetIndex].z;
				voxelStaticHost[i].relaxIndex = relaxationIndexHost[i];
				voxelStaticHost[i].magn0Short = phantom[i].getMagn0() * info.nucleus.shortT2Weight;
				voxelStaticHost[i].magn0Long = phantom[i].getMagn0() * info.nucleus.longT2Weight;
				voxelStaticHost[i].delB0 = phantom[i].bInfo.delB0;
				voxelStaticHost[i].devDelB0X = phantom[i].bInfo.devDelB0.x;
				voxelStaticHost[i].devDelB0Y = phantom[i].bInfo.devDelB0.y;
				voxelStaticHost[i].devDelB0Z = phantom[i].bInfo.devDelB0.z;
				voxelStaticHost[i].delGradX = phantom[i].bInfo.delGradX;
				voxelStaticHost[i].delGradY = phantom[i].bInfo.delGradY;
				voxelStaticHost[i].delGradZ = phantom[i].bInfo.delGradZ;

				voxelDynamicHost[i].shortPool = makeMagnetizationPool(
					magn.x * info.nucleus.shortT2Weight,
					magn.y * info.nucleus.shortT2Weight,
					magn.z * info.nucleus.shortT2Weight);
				voxelDynamicHost[i].longPool = makeMagnetizationPool(
					magn.x * info.nucleus.longT2Weight,
					magn.y * info.nucleus.longT2Weight,
					magn.z * info.nucleus.longT2Weight);

				for (unsigned short int tx = 0; tx < numTx; tx++)
				{
					const std::complex<float> value = phantom[i].bInfo.b1Plus[tx];
					b1PlusHost[(size_t)i * (size_t)numTx + (size_t)tx] = makeComplex(value.real(), value.imag());
				}
				for (unsigned short int rx = 0; rx < numRx; rx++)
				{
					const std::complex<float> value = phantom[i].bInfo.b1Mins[rx];
					b1MinsHost[(size_t)rx * (size_t)voxelCount + (size_t)i] = makeComplex(value.real(), value.imag());
				}
			}

			for (unsigned int timeIndex = 0; timeIndex < (unsigned int)sequence.time.size(); timeIndex++)
			{
				float stepBaseZ = 0.0f;
				bool rfActive = false;
				for (unsigned short int tx = 0; tx < numTx; tx++)
				{
					const size_t sequenceIndex = (size_t)timeIndex * (size_t)numTx + (size_t)tx;
					const std::complex<float> rfValue = sequence.rf[tx][timeIndex];
					rfSequenceHost[sequenceIndex] = makeComplex(rfValue.real(), rfValue.imag());
					if (!(rfValue.real() == 0.0f && rfValue.imag() == 0.0f))
					{
						rfActive = true;
					}
					stepBaseZ += sequence.delFreq[tx][timeIndex] * delFreqScale;
				}
				stepBaseZHost[timeIndex] = stepBaseZ;
				rfActiveHost[timeIndex] = rfActive ? 1u : 0u;

				const size_t relaxationBaseIndex = (size_t)timeIndex * (size_t)relaxTypeCount;
				for (unsigned int relaxIndex = 0; relaxIndex < relaxTypeCount; relaxIndex++)
				{
					relaxationFullHost[relaxationBaseIndex + (size_t)relaxIndex] = makeRelaxationHost(sequence.time[timeIndex], relaxationKeys[relaxIndex]);
					const float timeToSampleSeconds = sequence.sampleOffset[timeIndex];
					relaxationBeforeHost[relaxationBaseIndex + (size_t)relaxIndex] = makeRelaxationHost(timeToSampleSeconds, relaxationKeys[relaxIndex]);
					relaxationAfterHost[relaxationBaseIndex + (size_t)relaxIndex] = makeRelaxationHost(sequence.time[timeIndex] - timeToSampleSeconds, relaxationKeys[relaxIndex]);
				}
			}

			return copyToDevice(deviceData(voxelStatic), voxelStaticHost.data(), voxelStatic.size(), "voxelStatic upload") &&
				copyToDevice(deviceData(voxelDynamic), voxelDynamicHost.data(), voxelDynamic.size(), "voxelDynamic upload") &&
				copyToDevice(deviceData(b1Plus), b1PlusHost.data(), b1Plus.size(), "b1Plus upload") &&
				copyToDevice(deviceData(b1Mins), b1MinsHost.data(), b1Mins.size(), "b1Mins upload") &&
				copyToDevice(deviceData(rfStep), rfSequenceHost.data(), rfStep.size(), "rfStep upload") &&
				copyToDevice(deviceData(relaxationFull), relaxationFullHost.data(), relaxationFull.size(), "relaxationFull upload") &&
				copyToDevice(deviceData(relaxationBefore), relaxationBeforeHost.data(), relaxationBefore.size(), "relaxationBefore upload") &&
				copyToDevice(deviceData(relaxationAfter), relaxationAfterHost.data(), relaxationAfter.size(), "relaxationAfter upload");
		}

		unsigned int voxelCount;
		unsigned int relaxTypeCount;
		unsigned short int numTx, numRx;
		float b0;
		float gammaHzPerT;
		float gammaRadPerTPerS;
		GpuVec3 wid;
		float signalPhaseScaleX;
		float signalPhaseScaleY;
		float signalVoxelVolume;
		size_t rfSharedBytes;
		int deviceIndex;
		std::string deviceName;
		// Owners allocate once after device selection and release automatically.
		thrust::device_vector<GpuVoxelStatic> voxelStatic;
		thrust::device_vector<GpuVoxelDynamic> voxelDynamic;
		thrust::device_vector<GpuComplex> b1Plus;
		thrust::device_vector<GpuComplex> b1Mins;
		thrust::device_vector<GpuComplex> rfStep;
		thrust::device_vector<GpuRelaxation> relaxationFull;
		thrust::device_vector<GpuRelaxation> relaxationBefore, relaxationAfter;
		thrust::device_vector<GpuComplexDouble> kSpaceSignal;
		std::vector<float> stepBaseZHost;
		std::vector<unsigned char> rfActiveHost;
		std::vector<GpuComplexDouble> kSpaceSignalHost;
	};
}

int runSimulationCudaImpl(Execution & run, CmdInterp & cmdInterp)
{
	Execution::Info & info = run.getInfo();
	Execution::Sequence & sequence = run.getSequence();
	std::vector<float> & intervalSeconds = sequence.time;
	std::vector<int> & acquisitionEvents = sequence.acq;
	std::vector<float> & gX = sequence.gX;
	std::vector<float> & gY = sequence.gY;
	std::vector<float> & gZ = sequence.gZ;

	unsigned int acquisitionCount = 0;
	for (unsigned int timeIndex = 0; timeIndex < intervalSeconds.size(); timeIndex++)
	{
		if (acquisitionEvents[timeIndex] == 1)
		{
			acquisitionCount++;
		}
	}

	CudaSimulationState state;
	if (!state.initialize(run, acquisitionCount))
	{
		return EXIT_FAILURE;
	}

	// Kernels borrow pointers; the state owns these buffers for the whole run.
	const GpuVoxelStatic * voxelStatic = deviceData(state.voxelStatic);
	GpuVoxelDynamic * voxelDynamic = deviceData(state.voxelDynamic);
	const GpuComplex * b1Plus = deviceData(state.b1Plus);
	const GpuComplex * b1Mins = deviceData(state.b1Mins);
	const GpuComplex * rfSequence = deviceData(state.rfStep);
	const GpuRelaxation * relaxationFull = deviceData(state.relaxationFull);
	const GpuRelaxation * relaxationBefore = deviceData(state.relaxationBefore);
	const GpuRelaxation * relaxationAfter = deviceData(state.relaxationAfter);
	GpuComplexDouble * kSpaceSignal = deviceData(state.kSpaceSignal);

	std::vector<std::vector<std::complex<float> > > signalSamples(info.numRx);
	std::vector<Vect3D<float> > trajectorySamples;
	for (unsigned short int rx = 0; rx < info.numRx; rx++)
	{
		signalSamples[rx].reserve(acquisitionCount);
	}
	trajectorySamples.reserve(acquisitionCount);
	// Nominal gradient integral, in cycles/m, sampled at the same ADC observation.
	Vect3D<float> kCyclesPerMeter;
	kCyclesPerMeter = 0;
	unsigned int acquisitionIndex = 0;

	const unsigned int intervalCount = (unsigned int)intervalSeconds.size();
	const unsigned int voxelCount = state.voxelCount;
	const int voxelBlocks = (int)((voxelCount + kCudaBlockSize - 1u) / kCudaBlockSize);

	std::cout << "Running CUDA backend on device " << state.deviceIndex << ": " << state.deviceName << "\n";
	ProgressReporter progress(intervalCount);
	CudaProgress completedProgress(progress, intervalCount);

	for (unsigned int timeIndex = 0; timeIndex < intervalCount; timeIndex++)
	{
		GpuVec3 gradientTeslaPerMeter = makeVec3(gX[timeIndex], gY[timeIndex], gZ[timeIndex]);
		const size_t sequenceIndex = (size_t)timeIndex * (size_t)info.numTx;
		const GpuComplex * rfStep = (state.numTx == 0) ? NULL : rfSequence + sequenceIndex;
		const float stepBaseZ = state.stepBaseZHost[timeIndex];
		const size_t relaxationIndex = (size_t)timeIndex * (size_t)state.relaxTypeCount;
		const GpuRelaxation * relaxationFullStep = relaxationFull + relaxationIndex;
		const GpuRelaxation * relaxationBeforeStep = relaxationBefore + relaxationIndex;
		const GpuRelaxation * relaxationAfterStep = relaxationAfter + relaxationIndex;
		const bool rfActive = state.rfActiveHost[timeIndex] != 0u;

		if (acquisitionEvents[timeIndex] == 1)
		{
			AcquisitionStep step;
			step.gradient = gradientTeslaPerMeter;
			step.voxelWidth = state.wid;
			step.baseFieldZ = stepBaseZ;
			step.timeToSampleSeconds = sequence.sampleOffset[timeIndex];
			step.timeAfterSampleSeconds = intervalSeconds[timeIndex] - step.timeToSampleSeconds;
			step.phaseScaleX = state.signalPhaseScaleX;
			step.phaseScaleY = state.signalPhaseScaleY;
			step.voxelVolume = state.signalVoxelVolume;
			step.b0 = state.b0;
			step.gammaRadPerTPerS = state.gammaRadPerTPerS;
			step.sampleIndex = acquisitionIndex;
			const bool launchOk = rfActive ?
				launchAcquisitionSignalKernel<true>(voxelStatic, voxelDynamic,
					b1Plus, b1Mins, rfStep, relaxationBeforeStep, relaxationAfterStep,
					state.voxelCount, state.numTx, state.numRx, step, kSpaceSignal) :
				launchAcquisitionSignalKernel<false>(voxelStatic, voxelDynamic,
					b1Plus, b1Mins, rfStep, relaxationBeforeStep, relaxationAfterStep,
					state.voxelCount, state.numTx, state.numRx, step, kSpaceSignal);
			if (!launchOk)
			{
				return EXIT_FAILURE;
			}

			if (gradientTeslaPerMeter.x != 0)
			{
				kCyclesPerMeter.x += state.gammaHzPerT * gradientTeslaPerMeter.x * step.timeToSampleSeconds;
			}
			if (gradientTeslaPerMeter.y != 0)
			{
				kCyclesPerMeter.y += state.gammaHzPerT * gradientTeslaPerMeter.y * step.timeToSampleSeconds;
			}
			if (gradientTeslaPerMeter.z != 0)
			{
				kCyclesPerMeter.z += state.gammaHzPerT * gradientTeslaPerMeter.z * step.timeToSampleSeconds;
			}

			trajectorySamples.push_back(kCyclesPerMeter);

			if (gradientTeslaPerMeter.x != 0)
			{
				kCyclesPerMeter.x += state.gammaHzPerT * gradientTeslaPerMeter.x * step.timeAfterSampleSeconds;
			}
			if (gradientTeslaPerMeter.y != 0)
			{
				kCyclesPerMeter.y += state.gammaHzPerT * gradientTeslaPerMeter.y * step.timeAfterSampleSeconds;
			}
			if (gradientTeslaPerMeter.z != 0)
			{
				kCyclesPerMeter.z += state.gammaHzPerT * gradientTeslaPerMeter.z * step.timeAfterSampleSeconds;
			}

			acquisitionIndex++;
		}
		else
		{
			if (rfActive)
			{
				applyStepKernel<<<voxelBlocks, kCudaBlockSize, state.rfSharedBytes>>>(voxelStatic, voxelDynamic, b1Plus, rfStep, relaxationFullStep, state.voxelCount, state.numTx, stepBaseZ, gradientTeslaPerMeter, state.wid, intervalSeconds[timeIndex], state.gammaRadPerTPerS);
			}
			else
			{
				applyStepOffKernel<<<voxelBlocks, kCudaBlockSize>>>(voxelStatic, voxelDynamic, relaxationFullStep, state.voxelCount, stepBaseZ, gradientTeslaPerMeter, state.wid, intervalSeconds[timeIndex], state.gammaRadPerTPerS);
			}
			if (!checkLaunch("non-acquisition step kernel launch"))
			{
				return EXIT_FAILURE;
			}

			// Full interval evolution precedes trajectory reset or ideal crushing.
			switch (acquisitionEvents[timeIndex])
			{
			case 0:
				if (gradientTeslaPerMeter.x != 0)
				{
					kCyclesPerMeter.x += state.gammaHzPerT * gradientTeslaPerMeter.x * intervalSeconds[timeIndex];
				}
				if (gradientTeslaPerMeter.y != 0)
				{
					kCyclesPerMeter.y += state.gammaHzPerT * gradientTeslaPerMeter.y * intervalSeconds[timeIndex];
				}
				if (gradientTeslaPerMeter.z != 0)
				{
					kCyclesPerMeter.z += state.gammaHzPerT * gradientTeslaPerMeter.z * intervalSeconds[timeIndex];
				}
				break;

			case -2: // Clear transverse M and derivatives, preserve pool Mz.
				if (!applyCrusher(voxelDynamic, state.voxelCount))
				{
					return EXIT_FAILURE;
				}
				/* fall through */
			case -1: // Reset the tracked trajectory while retaining evolved spin state.
				kCyclesPerMeter = 0;
				break;

			default:
				progress.finishLine();
				std::cout << "WARNING: Error in sequence file: see time index #" << timeIndex << std::endl;
				std::cout << "Value causing error is " << acquisitionEvents[timeIndex] << std::endl;
				std::cout << "Sequence file only accepts values 1, 0, -1, and -2.\n";
				std::cout << "Press enter to continue simulation.\n";
				std::cin.get();
				break;
			}
		}

		if (!completedProgress.submitted(timeIndex + 1u)) return EXIT_FAILURE;
	}
	if (!completedProgress.finish()) return EXIT_FAILURE;

	if (!copyToHost(state.kSpaceSignalHost.data(), kSpaceSignal, state.kSpaceSignal.size(), "k-space download"))
	{
		return EXIT_FAILURE;
	}

	for (unsigned int sampleIndex = 0; sampleIndex < acquisitionCount; sampleIndex++)
	{
		for (unsigned short int rx = 0; rx < info.numRx; rx++)
		{
			const GpuComplexDouble & value = state.kSpaceSignalHost[(size_t)sampleIndex * (size_t)info.numRx + (size_t)rx];
			signalSamples[rx].push_back(std::complex<float>((float)value.real, (float)value.imag));
		}
	}

	progress.finishLine();
	double TheTime = progress.elapsedSeconds();
	printf("ID %d used %f seconds.\n", 0, TheTime);

	run.setKSpace(signalSamples);
	if (!run.expPhantomKSpace(cmdInterp)) return EXIT_FAILURE;

	run.setKMap(trajectorySamples);
	if (!run.expPhantomKMap(cmdInterp)) return EXIT_FAILURE;

	printf("Execution completed, press enter to exit.\n");
	std::cin.get();

	return EXIT_SUCCESS;
}
