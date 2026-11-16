#include "ModelInputs.h"

#include <array>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <sys/stat.h>
#include <zlib.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

namespace {
bool exists(const std::string &path)
{
#ifdef _WIN32
    struct _stat64 info;
    return _stat64(path.c_str(), &info) == 0;
#else
    struct stat info;
    return stat(path.c_str(), &info) == 0;
#endif
}

std::string createTempFile()
{
#ifdef _WIN32
    char directory[MAX_PATH], path[MAX_PATH];
    const DWORD length = GetTempPathA(MAX_PATH, directory);
    if (length && length < MAX_PATH && GetTempFileNameA(directory, "xmr", 0, path))
        return path;
#else
    const char *directory = std::getenv("TMPDIR");
    std::string path = std::string(directory ? directory : "/tmp") + "/xudomri-XXXXXX";
    const int file = mkstemp(&path[0]);
    if (file >= 0) {
        close(file);
        return path;
    }
#endif
    throw std::runtime_error("Unable to create a temporary model input file.");
}

void expandGzip(const std::string &source, const std::string &target)
{
    gzFile gzip = gzopen(source.c_str(), "rb");
    if (!gzip)
        throw std::runtime_error("Unable to open gzip input: " + source);

    try {
        if (gzdirect(gzip))
            throw std::runtime_error("Input is not gzip data: " + source);

        std::ofstream output(target, std::ios::binary | std::ios::trunc);
        if (!output)
            throw std::runtime_error("Unable to open temporary input: " + target);
        std::array<char, 64 * 1024> buffer;
        int count;
        while ((count = gzread(gzip, buffer.data(), static_cast<unsigned>(buffer.size()))) > 0) {
            if (!output.write(buffer.data(), count))
                throw std::runtime_error("Unable to expand " + source + " to " + target);
        }
        int status;
        gzerror(gzip, &status);
        if (count < 0 || status != Z_OK)
            throw std::runtime_error("Corrupt or incomplete gzip input: " + source);
        output.close();
        if (!output)
            throw std::runtime_error("Unable to finish writing temporary input: " + target);
    } catch (...) {
        gzclose(gzip);
        throw;
    }
    if (gzclose(gzip) != Z_OK)
        throw std::runtime_error("Unable to finish reading gzip input: " + source);
}
}

namespace nutate {
ModelInputs::~ModelInputs()
{
    for (const auto &path : temporaryFiles)
        std::remove(path.c_str());
}

void ModelInputs::prepare(std::string &path)
{
    if (path.empty() || path == "NULL")
        return;
    const auto size = path.size();
    const bool compressed = size >= 3 && path[size - 3] == '.'
        && (path[size - 2] == 'g' || path[size - 2] == 'G')
        && (path[size - 1] == 'z' || path[size - 1] == 'Z');
    if (!compressed && exists(path))
        return;
    const std::string source = compressed ? path : path + ".gz";
    if (!compressed && !exists(source))
        return; // The existing reader reports the missing input.

    temporaryFiles.emplace_back();
    temporaryFiles.back() = createTempFile();
    std::cout << "Expanding gzip input: " << source << " -> " << temporaryFiles.back() << '\n';
    expandGzip(source, temporaryFiles.back());
    path = temporaryFiles.back();
}

void ModelInputs::prepare(std::vector<std::string> &paths)
{
    for (auto &path : paths)
        prepare(path);
}
} // namespace nutate
