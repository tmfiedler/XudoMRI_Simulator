// Small deterministic checks; run from the noise build with CTest.
#include "../SequenceFile.h"
#include "ThermalMagnetization.h"
#include "NumericArguments.h"
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
        // Independent parser boundaries: no file loading or physics helper.
        float numeric = 0;
        unsigned short count = 0;
        for (const char* bad : {"", "garbage", "3garbage", "nan", "inf", "1e999", "1e-999", "1e-46"})
            check(!nutate::finiteFloatArgument(bad,"B0",numeric),"Invalid B0 accepted");
        check(nutate::finiteFloatArgument("-3","B0",numeric) && numeric == -3,"Signed B0 rejected");
        check(nutate::finiteFloatArgument("0","B0",numeric) && numeric == 0,"Zero B0 rejected");
        check(nutate::finiteFloatArgument("3e0","B0",numeric) && numeric == 3,"Scientific notation rejected");
        for (const char* bad : {"0", "-1", "1.5", "65536", "65535.0001", "1x", "nan"})
            check(!nutate::positiveCountArgument(bad,"NumIso",count),"Invalid count accepted");
        check(nutate::positiveCountArgument("65535","Thread",count) && count == 65535,"Count limit rejected");
        check(nutate::positiveCountArgument("1e0","NumIso",count) && count == 1,"Integral exponent rejected");
        for (const char* bad : {"1.5", "1x", "08", "2147483648", "16777217", "-2147483649"})
            check(!nutate::indexArgument(bad,"xMin",numeric),"Invalid index accepted");
        check(nutate::indexArgument("-0x10","xMin",numeric) && numeric == -16,"Hex index rejected");
        check(nutate::indexArgument("010","xMax",numeric) && numeric == 8,"Octal index rejected");
        for (const char* bad : {"0", "-1", "1e-43", "2mm"})
            check(!nutate::positiveWidthArgument(bad,"xWid",numeric),"Invalid width accepted");
        check(nutate::positiveWidthArgument(".5","xWid",numeric) && numeric == .5f,"Valid width rejected");

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
        std::cout << "PASS: numeric arguments, thermal scaling and V1 sequence contracts.\n";
        return 0;
    }
    catch (const std::exception& e)
    {
        std::remove(fixture);
        std::cerr << "FAIL: " << e.what() << '\n';
        return 1;
    }
}
