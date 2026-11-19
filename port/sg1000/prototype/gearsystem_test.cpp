// Optional integration test against a local Gearsystem source checkout.
#include "GearsystemCore.h"
#include "Memory.h"
#include <cassert>
#include <cstdio>
#include <vector>

bool g_mcp_stdio_mode = false;

struct Simulation {
    GearsystemCore core;
    std::vector<u8> video;
    std::vector<s16> audio;
    Simulation(const char* rom) : video(320 * 288 * 4), audio(16384) {
        core.Init();
        Cartridge::ForceConfiguration config{Cartridge::CartridgeSG1000Mapper,
            Cartridge::CartridgeUnknownZone, Cartridge::CartridgeNTSC,
            Cartridge::CartridgeSG1000};
        assert(core.LoadROM(rom, &config));
        frames(15);
    }
    void frames(int count) {
        int samples = 0;
        while (count--) core.RunToVBlank(video.data(), audio.data(), &samples);
    }
    int word(int addr) {
        auto m = core.GetMemory();
        return m->Retrieve(addr) | (m->Retrieve(addr + 1) << 8);
    }
    int byte(int addr) { return core.GetMemory()->Retrieve(addr); }
    int x() { return (word(0xC000) >> 8) + 256 * byte(0xC011); }
    int y() { return (word(0xC002) >> 8) + 256 * byte(0xC012); }
    int camera_x() { return byte(0xC013); }
    int camera_y() { return byte(0xC014); }
    int vx() { return static_cast<short>(word(0xC004)); }
    int grounded() { return core.GetMemory()->Retrieve(0xC008); }
    void press(GS_Keys key) { core.KeyPressed(Joypad_1, key); }
    void release(GS_Keys key) { core.KeyReleased(Joypad_1, key); }
};

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    Simulation s(argv[1]);
    assert(s.x() == 24 && s.y() == 176 && s.grounded());
    int start_camera_y = s.camera_y();
    s.press(Key_Right);
    s.frames(60);
    assert(s.x() == 133 && s.y() == 120 && s.vx() == 0x300 && s.grounded());
    assert(s.camera_x() > 0 && s.camera_y() < start_camera_y);
    s.frames(30);
    assert(s.x() == 223 && s.y() == 112 && s.grounded());
    s.frames(300);
    assert(s.x() == 744 && s.vx() == 0 && s.camera_x() == 64);
    s.release(Key_Right);
    s.press(Key_1);
    s.frames(10);
    assert(s.y() < 192 && !s.grounded());
    s.release(Key_1);
    s.frames(60);
    assert(s.y() == 192 && s.grounded());
    s.press(Key_Left);
    s.frames(350);
    assert(s.x() == 0 && s.vx() == 0 && s.camera_x() == 0 && s.grounded());
    Simulation short_jump(argv[1]);
    short_jump.press(Key_1);
    short_jump.frames(1);
    short_jump.release(Key_1);
    int short_apex = 255;
    for (int i = 0; i < 90; ++i) {
        short_jump.frames(1);
        if (short_jump.y() < short_apex) short_apex = short_jump.y();
    }
    Simulation held_jump(argv[1]);
    held_jump.press(Key_1);
    int held_apex = 255;
    for (int i = 0; i < 90; ++i) {
        if (i == 16) held_jump.release(Key_1);
        held_jump.frames(1);
        if (held_jump.y() < held_apex) held_apex = held_jump.y();
    }
    assert(held_apex < short_apex && held_jump.grounded());
    Simulation brake(argv[1]);
    brake.press(Key_Right);
    brake.frames(30);
    assert(brake.vx() > 0);
    brake.release(Key_Right);
    brake.press(Key_Left);
    brake.frames(30);
    assert(brake.vx() < 0);
    Simulation viewer(argv[1]);
    viewer.press(Key_2);
    viewer.press(Key_Right);
    viewer.frames(2);
    assert(viewer.byte(0xC00D) == 1 && viewer.x() == 24);
    viewer.frames(5);
    assert(viewer.byte(0xC00D) == 1); // Holding does not skip frames.
    viewer.release(Key_Right);
    viewer.frames(2);
    viewer.press(Key_Right);
    viewer.frames(2);
    assert(viewer.byte(0xC00D) == 2 && viewer.x() == 24);
    viewer.release(Key_2);
    viewer.frames(20);
    assert(viewer.x() > 24);
    std::puts("Gearsystem SG-1000 physics smoke tests passed");
}
