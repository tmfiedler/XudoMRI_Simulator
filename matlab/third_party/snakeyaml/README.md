# Bundled YAML parser

SnakeYAML 2.3, https://bitbucket.org/snakeyaml/snakeyaml/ (Apache 2.0).
Artifact: https://repo.maven.apache.org/maven2/org/yaml/snakeyaml/2.3/snakeyaml-2.3.jar
SHA-256: 63a76fe66b652360bd4c2c107e6f0258daa7d4bb492008ba8c26fcd230ff9146

readNucleusConfig adds this jar to MATLAB’s dynamic Java class path and uses
SafeConstructor/node composition; it does not construct arbitrary YAML objects.
No external installation or network access is needed at runtime.
