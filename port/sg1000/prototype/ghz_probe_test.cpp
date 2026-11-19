// Execute the actual Z80 GHZ lookup routines under Gearsystem.
#include "GearsystemCore.h"
#include "Memory.h"
#include <cassert>
#include <cstdio>
#include <vector>
#include <fstream>

bool g_mcp_stdio_mode = false;
int main(int argc, char** argv) {
    if (argc != 4) return 2;
    auto read = [](const char* path) {
        std::ifstream f(path, std::ios::binary);
        assert(f);
        return std::vector<unsigned char>(std::istreambuf_iterator<char>(f), {});
    };
    auto types = read(argv[2]);
    auto profiles = read(argv[3]);
    GearsystemCore core;
    std::vector<u8> video(320 * 288 * 4);
    std::vector<s16> audio(16384);
    core.Init();
    Cartridge::ForceConfiguration config{Cartridge::CartridgeSG1000Mapper,
        Cartridge::CartridgeUnknownZone, Cartridge::CartridgeNTSC,
        Cartridge::CartridgeSG1000};
    assert(core.LoadROM(argv[1], &config));
    int samples = 0;
    auto frame = [&] { core.RunToVBlank(video.data(), audio.data(), &samples); };
    for (int i = 0; i < 15; ++i) frame();
    Memory* m = core.GetMemory();
    for (int y = 0; y < 16; ++y) {
        for (int x = 0; x < 256; x += 7) {
            int offset = (x + y) & 31;
            m->Load(0xC030, y);
            m->Load(0xC031, x);
            m->Load(0xC032, offset);
            frame();
            int expected = types[y * 256 + x];
            assert(m->Retrieve(0xC033) == expected);
            assert(m->Retrieve(0xC034) == profiles[expected * 32 + offset]);
        }
    }
    m->Load(0xC030, 16);
    frame();
    assert(m->Retrieve(0xC033) == 0);
    std::puts("Gearsystem GHZ1 collision lookup tests passed");
}
