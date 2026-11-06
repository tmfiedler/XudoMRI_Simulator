function kernelTable = buildKaiserTable(kernelWidth,beta,tableSize)
%BUILDKAISERTABLE Tabulate the normalized Kaiser-Bessel kernel.
    halfWidth = kernelWidth / 2;
    radius = linspace(0,halfWidth,tableSize);
    kernelTable.radius = radius;
    kernelTable.value = kaiserBesselKernel(radius,kernelWidth,beta);
    kernelTable.halfWidth = halfWidth;
end

function value = kaiserBesselKernel(distance,kernelWidth,beta)
    distance = abs(distance);
    halfWidth = kernelWidth / 2;
    value = zeros(size(distance));
    mask = distance <= halfWidth;
    if any(mask(:))
        argument = sqrt(max(0,1 - (distance(mask) ./ halfWidth).^2));
        value(mask) = besseli(0,beta * argument) / besseli(0,beta);
    end
end
