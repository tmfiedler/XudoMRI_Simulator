function [gammaRadPerTPerS,gammaHzPerT] = getNucleusGamma(name)
%GETNUCLEUSGAMMA Gamma for an exact configured ID; units are explicit.
definition = getNucleusDefinition(name);
gammaRadPerTPerS = definition.gammaRadPerTPerS;
gammaHzPerT = definition.gammaHzPerT;
end
