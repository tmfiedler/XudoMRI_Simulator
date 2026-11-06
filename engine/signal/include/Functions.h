/*=========================================================================

  Program:   NutateSignal
  Module:    $RCSfile: Functions.h,v $
  Language:  C++
  Date:      $Date: 2009/12/09 18:54:15 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#ifndef FUNCTIONS_H
#define FUNCTIONS_H

#include <chrono>
#include <atomic>
#include <cstdint>
#include <cstddef>
#include <mutex>
#include <vector>

float sinc(float x);

struct ProgressEstimate
{
	unsigned int tenthsPercent;
	double remainingSeconds;
	bool estimating;
};

// Completed model work, not submitted work or a promise of future wall time.
ProgressEstimate estimateProgress(std::uint64_t total, std::uint64_t completed,
	double elapsedSeconds, bool finished = false);

class ProgressReporter
{
public:
	explicit ProgressReporter(std::uint64_t totalWork);
	~ProgressReporter();

	void update(std::uint64_t completedWork);
	void addCompletedWork(std::uint64_t work);
	void complete();
	void finishLine();
	double elapsedSeconds() const;

private:
	void printLine(float progressPercent, double remainingSeconds, bool estimating);

	std::uint64_t totalWork_;
	std::atomic<std::uint64_t> completedWork_;
	std::mutex reportMutex_;
	int lastTenthsPercent_;
	std::size_t lastLineLength_;
	bool lineActive_;
	std::chrono::steady_clock::time_point startTime_;
};

#endif /* FUNCTIONS_H */
