#pragma once

#include <string>
#include <vector>

namespace nutate {

// Owns expanded copies for the lifetime of a CLI run.
class ModelInputs {
public:
    ModelInputs() = default;
    ~ModelInputs();
    ModelInputs(const ModelInputs &) = delete;
    ModelInputs &operator=(const ModelInputs &) = delete;

    void prepare(std::string &path);
    void prepare(std::vector<std::string> &paths);

private:
    std::vector<std::string> temporaryFiles;
};

} // namespace nutate
