/*=========================================================================

  Program:   NutateSignal
  Module:    $RCSfile: Functions.cpp,v $
  Language:  C++
  Date:      $Date: 2009/12/09 18:54:15 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#include "Functions.h"

#include <math.h>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdlib.h>
#include <string>
#include <algorithm>
#include <cmath>

namespace
{
	std::string formatDuration(double seconds)
	{
		if (seconds < 0.0)
		{
			seconds = 0.0;
		}

		const unsigned long long totalSeconds = (unsigned long long)(seconds + 0.5);
		const unsigned long long hours = totalSeconds / 3600ull;
		const unsigned long long minutes = (totalSeconds % 3600ull) / 60ull;
		const unsigned long long remainingSeconds = totalSeconds % 60ull;

		std::ostringstream stream;
		stream << std::setfill('0')
			<< std::setw(2) << hours << ":"
			<< std::setw(2) << minutes << ":"
			<< std::setw(2) << remainingSeconds;
		return stream.str();
	}
}

float sinc(float x)
{
	if (x == 0)
	{
		return (float) 1;
	}
	else
	{
		return (float) (sin(x)/x);
	}
}

ProgressEstimate estimateProgress(std::uint64_t total, std::uint64_t completed,
	double elapsed, bool finished)
{
	completed = std::min(completed, total);
	ProgressEstimate result = { 0u, 0.0, true };
	if (finished)
	{
		result.tenthsPercent = 1000u;
		result.estimating = false;
		return result;
	}
	if (total != 0u)
	{
		// Floor the displayed tenths: incomplete work must never round to100%.
		result.tenthsPercent = std::min(999u,
			(unsigned int)(1000.0L * completed / total));
	}
	if (completed != 0u && std::isfinite(elapsed) && elapsed >= 0.0)
	{
		result.remainingSeconds = elapsed * (double)(total - completed) / (double)completed;
		result.estimating = false;
	}
	return result;
}

ProgressReporter::ProgressReporter(std::uint64_t totalWork)
	: totalWork_(totalWork)
	, completedWork_(0u)
	, lastTenthsPercent_(0)
	, lastLineLength_(0u)
	, lineActive_(false)
	, startTime_(std::chrono::steady_clock::now())
{
	printLine(0.0f, 0.0, true);
}

ProgressReporter::~ProgressReporter()
{
	finishLine();
}

void ProgressReporter::update(std::uint64_t completedWork)
{
	const std::lock_guard<std::mutex> lock(reportMutex_);
	const ProgressEstimate estimate = estimateProgress(totalWork_, completedWork, elapsedSeconds());
	const int tenthsPercent = (int)estimate.tenthsPercent;
	if (tenthsPercent <= lastTenthsPercent_)
	{
		return;
	}

	printLine((float)tenthsPercent / 10.0f, estimate.remainingSeconds, estimate.estimating);
	lastTenthsPercent_ = tenthsPercent;
}

void ProgressReporter::addCompletedWork(std::uint64_t work)
{
	const std::uint64_t completed = completedWork_.fetch_add(work, std::memory_order_relaxed) + work;
	update(completed);
}

void ProgressReporter::complete()
{
	const std::lock_guard<std::mutex> lock(reportMutex_);
	lastTenthsPercent_ = 1000;
	printLine(100.0f, 0.0, false);
	finishLine();
	std::cout << "Finalizing simulation outputs..." << std::endl;
}

void ProgressReporter::finishLine()
{
	if (lineActive_)
	{
		std::cout << std::endl;
		lineActive_ = false;
		lastLineLength_ = 0u;
	}
}

double ProgressReporter::elapsedSeconds() const
{
	return std::chrono::duration<double>(std::chrono::steady_clock::now() - startTime_).count();
}

void ProgressReporter::printLine(float progressPercent, double remainingSeconds, bool estimating)
{
	std::ostringstream stream;
	stream << "Calculating " << std::fixed << std::setprecision(1) << progressPercent << "% done, remaining time ";
	if (estimating)
	{
		stream << "estimating...";
	}
	else
	{
		stream << formatDuration(remainingSeconds);
	}

	const std::string line = stream.str();
	std::cout << '\r' << line;
	if (lastLineLength_ > line.size())
	{
		std::cout << std::string(lastLineLength_ - line.size(), ' ');
	}
	std::cout << std::flush;

	lastLineLength_ = line.size();
	lineActive_ = true;
}
