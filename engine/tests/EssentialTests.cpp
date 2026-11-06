// Small deterministic checks; run from the noise build with CTest.
#include "../SequenceFile.h"
#include "ThermalMagnetization.h"
#include <cstdio>
#include <iostream>

static void check(bool ok, const char* message)
{
    if (!ok) throw std::runtime_error(message);
}

int main()
{
    const char* fixture = "essential-sequence.seqn";
    try
    {
        // Independent SI Curie-law values at 310 K, in A/m/T per mol/L.
        // hbar=1.0545718176461565e-34, angular gamma=2*pi*gamma_Hz.
        nutate::NucleusDefinition proton{"1H", 42576000, 0.5,
            relax_monoexponential, 1, 0};
        nutate::NucleusDefinition sodium{"23Na", 11262000, 1.5,
            relax_biexponential, 0.6f, 0.4f};
        check(std::abs(nutate::equilibriumPerTeslaPerMolPerL(proton,310) /
            2.799546644231083e-5 - 1) < 1e-12, "Proton thermal scaling");
        check(std::abs(nutate::equilibriumPerTeslaPerMolPerL(sodium,310) /
            9.793976187283856e-6 - 1) < 1e-12, "Sodium thermal scaling");

        // Four steps, no Tx, one Rx, two ADC midpoints in a 10 mT/m gradient.
        float raw[] = {-1,1,4,0,1,
            4,1,0.2f,0.2f,0,0, 4,1,1,1,-1,-2,
            4,1,0.1f,0.1f,0,0, 4,1,0.2f,0.2f,0,0,
            4,1,10,10,0,0, 1,4,0, 1,4,0};
        auto write = [&]() {
            std::ofstream out(fixture,std::ios::binary);
            out.write(reinterpret_cast<const char*>(raw),sizeof(raw));
            check(out.good(),"Cannot write fixture");
        };
        write();
        SequenceFile::Data data; std::string error;
        const bool valid = SequenceFile::read(fixture,true,data,error);
        check(valid,error.c_str());
        check(data.count==4 && data.tx==0 && data.rx==1,"Channel/count decode");
        check(data.acq==std::vector<int>({1,1,-1,-2}),"ADC/control flags");
        check(std::abs(data.time[0]-0.0002f)<1e-10f &&
            std::abs(data.sampleOffset[0]-0.0001f)<1e-10f &&
            std::abs(data.dwell[0]-0.0002f)<1e-10f &&
            std::abs(data.gx[0]-0.01f)<1e-8f,"Units and midpoint metadata");
        raw[1]=2; write();
        check(!SequenceFile::read(fixture,true,data,error),"Retired format accepted");
        raw[1]=1; raw[4]=0; write();
        check(!SequenceFile::read(fixture,true,data,error),"Zero receivers accepted");
        std::remove(fixture);
        std::cout << "PASS: thermal scaling and V1 sequence contracts.\n";
        return 0;
    }
    catch (const std::exception& e)
    {
        std::remove(fixture);
        std::cerr << "FAIL: " << e.what() << '\n';
        return 1;
    }
}
