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
    Simulation(const char* rom, bool auto_start = true) : video(320 * 288 * 4), audio(16384) {
        core.Init();
        Cartridge::ForceConfiguration config{Cartridge::CartridgeSG1000Mapper,
            Cartridge::CartridgeUnknownZone, Cartridge::CartridgeNTSC,
            Cartridge::CartridgeSG1000};
        assert(core.LoadROM(rom, &config));
        frames(15);
        if (auto_start) {
            press(Key_1);
            frames(2);
            release(Key_1);
            frames(3);
        }
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
    void set_byte(int addr, int value) { core.GetMemory()->Load(addr, value & 255); }
    void set_word(int addr, int value) { set_byte(addr, value); set_byte(addr + 1, value >> 8); }
    void set_x(int value) { set_word(0xC000, (value & 255) << 8); set_byte(0xC011, value >> 8); }
    void set_y(int value) { set_word(0xC002, (value & 255) << 8); set_byte(0xC012, value >> 8); }
    int x() { return (word(0xC000) >> 8) + 256 * byte(0xC011); }
    int y() { return (word(0xC002) >> 8) + 256 * byte(0xC012); }
    int camera_x() { return byte(0xC013); }
    int camera_y() { return byte(0xC014); }
    int vx() { return static_cast<short>(word(0xC004)); }
    int grounded() { return core.GetMemory()->Retrieve(0xC008); }
    int sprite_y() { return core.GetVideo()->GetVRAM()[0x1B00]; }
    int expected_sprite_y(int offset) { return (y() - camera_y() * 8 + offset - 1) & 255; }
    void press(GS_Keys key) { core.KeyPressed(Joypad_1, key); }
    void release(GS_Keys key) { core.KeyReleased(Joypad_1, key); }
};

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    Simulation menu(argv[1], false);
    auto vram = menu.core.GetVideo()->GetVRAM();
    const u8 title[] = {8, 9, 10, 11, 0, 12, 11, 13, 11, 14, 15};
    const u8 option[] = {2, 0, 15, 11, 12, 15};
    for (int i = 0; i < 11; ++i) assert(vram[0x190A + i] == title[i]);
    for (int i = 0; i < 6; ++i) assert(vram[0x198D + i] == option[i]);
    const u8 ghz[] = {0, 0, 16, 17, 8, 18};
    for (int i = 0; i < 6; ++i) assert(vram[0x19CD + i] == ghz[i]);
    assert(vram[0x1B00] == 0xD0);
    menu.press(Key_Right);
    menu.frames(5);
    assert(menu.x() == 24 && vram[0x190A] == 8);
    menu.release(Key_Right);
    menu.press(Key_1);
    menu.frames(4);
    assert(vram[0x190A] == 8); // A held confirmation does not start the game.
    menu.release(Key_1);
    menu.frames(4);
    assert(vram[0x190A] != 8 && menu.grounded() && menu.y() == 176);
    Simulation button2(argv[1], false);
    auto vram2 = button2.core.GetVideo()->GetVRAM();
    button2.press(Key_2);
    button2.frames(3);
    assert(vram2[0x198D] == 0 && vram2[0x19CD] == 2);
    button2.frames(10); // Held button must not repeatedly toggle.
    assert(vram2[0x19CD] == 2);
    button2.release(Key_2);
    button2.frames(2);
    button2.press(Key_1);
    button2.frames(3);
    button2.release(Key_1);
    button2.frames(40);
    assert(button2.byte(0xC01A) == 1); // GHZ1 selected
    assert(button2.x() == 256 && button2.y() == 368 && button2.grounded());
    assert(vram2[0x2000] == 0x37); // green foreground, cyan background
    assert(button2.camera_x() == 21 && button2.camera_y() == 37);
    for (int i = 0; i < 32; ++i) {
        assert(vram2[0x1800 + i] == 0);          // sky
        assert(vram2[0x1800 + 15 * 32 + i] == 1); // ground
    }
    // Start below the original start platform, travel up through it, then
    // land on its top on the way down (one-way collision).
    button2.set_y(380);
    button2.set_word(0xC006, 0xFC80);
    button2.set_byte(0xC008, 0);
    int min_y = 1000;
    bool passed_upward = false;
    for (int i = 0; i < 150; ++i) {
        button2.frames(1);
        if (button2.y() < min_y) min_y = button2.y();
        passed_upward |= button2.y() < 368 && !button2.grounded();
    }
    assert(passed_upward && min_y < 368);
    assert(button2.y() == 368 && button2.grounded());
    int ghz_tick_before = button2.byte(0xC00C);
    button2.press(Key_Right);
    button2.frames(120);
    int ghz_ticks = (button2.byte(0xC00C) - ghz_tick_before) & 255;
    std::printf("GHZ updates in 120 video frames: %d\n", ghz_ticks);
    assert(ghz_ticks >= 100);
    button2.release(Key_Right);
    button2.frames(10);
    assert(button2.x() > 270);
    // Far beyond TEST's 768px world and beyond the old 8-bit camera range.
    button2.set_x(3000);
    button2.frames(20);
    assert(button2.x() >= 2990);
    assert(button2.byte(0xC01E) > 0); // high byte of tile camera x
    // The header's right camera boundary is 6336; Sonic is clamped to
    // 6559, just inside the corresponding screen edge.
    button2.set_x(6550);
    button2.set_y(160);
    button2.set_word(0xC004, 0x0300);
    button2.set_word(0xC006, 0);
    button2.set_byte(0xC008, 0);
    button2.press(Key_Right);
    button2.frames(20);
    button2.release(Key_Right);
    assert(button2.x() == 6559 && button2.vx() == 0);
    assert(button2.camera_x() + 256 * button2.byte(0xC01E) == 792);
    button2.set_y(511);
    button2.set_word(0xC006, 0x0100);
    button2.set_byte(0xC008, 0);
    button2.frames(50);
    assert(button2.x() == 256 && button2.y() == 368 && button2.grounded());
    Simulation s(argv[1]);
    assert(s.x() == 24 && s.y() == 176 && s.grounded());
    int start_camera_y = s.camera_y();
    s.press(Key_Right);
    s.frames(60);
    assert(s.x() == 133 && s.y() == 120 && s.vx() == 0x300 && s.grounded());
    assert(s.camera_x() == (s.x() - 88) / 8 && s.camera_y() < start_camera_y);
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
    brake.frames(50);
    assert(brake.vx() > 0);
    brake.release(Key_Right);
    brake.press(Key_Left);
    brake.frames(2);
    assert(brake.vx() > 0 && brake.byte(0xC00B) == 0);
    assert(brake.byte(0xC00D) == 0x13 || brake.byte(0xC00D) == 0x25);
    bool saw_second_skid_frame = false;
    for (int i = 0; i < 10; ++i) {
        brake.frames(1);
        saw_second_skid_frame |= brake.byte(0xC00D) == 0x25;
    }
    assert(saw_second_skid_frame);
    brake.frames(20);
    assert(brake.vx() < 0);
    Simulation poses(argv[1]);
    poses.press(Key_Up);
    poses.frames(4);
    assert(poses.byte(0xC00D) == 0x14 && poses.vx() == 0);
    poses.press(Key_Right);
    poses.frames(5);
    assert(poses.vx() > 0 && poses.byte(0xC00D) != 0x14);
    poses.frames(50);
    assert(poses.byte(0xC00D) >= 0x0D && poses.byte(0xC00D) <= 0x10);
    // At fixed speeds, the original walking phase increases faster when
    // Sonic moves faster. Normal coasting subtracts 8 before animation.
    Simulation slow_walk(argv[1]);
    Simulation fast_walk(argv[1]);
    for (int i = 0; i < 12; ++i) {
        slow_walk.set_word(0xC004, 0x0108);
        fast_walk.set_word(0xC004, 0x0208);
        slow_walk.frames(1);
        fast_walk.frames(1);
    }
    assert(slow_walk.byte(0xC01B) == 1 && fast_walk.byte(0xC01B) == 1);
    assert(slow_walk.byte(0xC01C) == 18 && fast_walk.byte(0xC01C) == 24);
    Simulation jump_animation(argv[1]);
    jump_animation.press(Key_1);
    bool saw_jump[5] = {};
    for (int i = 0; i < 25; ++i) {
        jump_animation.frames(1);
        int frame = jump_animation.byte(0xC00D);
        if (frame >= 8 && frame <= 12) saw_jump[frame - 8] = true;
    }
    for (bool seen : saw_jump) assert(seen);
    Simulation idle(argv[1]);
    idle.frames(100);
    assert(idle.byte(0xC00D) == 0x06);
    idle.frames(230);
    assert(idle.byte(0xC00D) == 0x06);
    idle.frames(40);
    for (int i = 0; i < 100; ++i) {
        idle.frames(1);
        int frame = idle.byte(0xC00D);
        assert(frame == 0x15 || frame == 0x16 || frame == 0x17);
    }
    // Force the sequence boundaries and the SMS loop back to index 34.
    idle.set_byte(0xC016, 0x68);
    idle.set_byte(0xC019, 1);
    const int phases[] = {0, 15, 16, 33, 34, 49, 50, 65};
    const int expected[] = {0x16, 0x16, 0x15, 0x15, 0x16, 0x16, 0x17, 0x17};
    for (int i = 0; i < 8; ++i) {
        idle.set_byte(0xC017, phases[i]);
        idle.frames(1);
        assert(idle.byte(0xC00D) == expected[i]);
    }
    assert(idle.byte(0xC017) == 34);
    idle.press(Key_Down);
    idle.frames(3);
    assert(idle.byte(0xC00D) == 0x07 && idle.vx() == 0);
    assert(idle.sprite_y() == idle.expected_sprite_y(8));
    idle.release(Key_Down);
    idle.frames(3);
    assert(idle.byte(0xC00D) == 0x06);
    assert(idle.sprite_y() == idle.expected_sprite_y(0));
    // Down while moving starts a ground roll. On flat ground it loses speed
    // and stays rolling after down is released, then returns to standing.
    Simulation roll(argv[1]);
    roll.press(Key_Right);
    roll.frames(12);
    roll.press(Key_Down);
    roll.release(Key_Right);
    roll.frames(2);
    assert(roll.grounded() && roll.byte(0xC015) == 1);
    assert(roll.byte(0xC00D) >= 8 && roll.byte(0xC00D) <= 12);
    int ball_frame = roll.byte(0xC00D);
    assert(roll.sprite_y() == roll.expected_sprite_y((ball_frame == 8 || ball_frame == 10) ? 9 : 8));
    int roll_speed = roll.vx();
    roll.release(Key_Down);
    roll.frames(2);
    assert(roll.byte(0xC015) == 1 && roll.vx() < roll_speed);
    roll.frames(100);
    assert(roll.vx() == 0 && roll.byte(0xC015) == 0);

    // The SMS rolling branch uses four 8.8 subpixels of flat drag per
    // frame, symmetrically. Same-direction input doesn't accelerate a roll.
    Simulation roll_flat_right(argv[1]);
    roll_flat_right.set_x(24);
    roll_flat_right.set_word(0xC004, 0x0200);
    roll_flat_right.set_byte(0xC015, 1);
    roll_flat_right.press(Key_Right);
    roll_flat_right.frames(5);
    assert(roll_flat_right.vx() == 0x0200 - 5 * 4 && roll_flat_right.byte(0xC015));
    Simulation roll_flat_left(argv[1]);
    roll_flat_left.set_x(72);
    roll_flat_left.set_word(0xC004, -0x0200);
    roll_flat_left.set_byte(0xC015, 1);
    roll_flat_left.press(Key_Left);
    roll_flat_left.frames(5);
    assert(roll_flat_left.vx() == -0x0200 + 5 * 4 && roll_flat_left.byte(0xC015));
    // With down held, opposing input doesn't interrupt the roll. Releasing
    // down while still holding opposite unrolls and applies standard braking.
    Simulation roll_brake(argv[1]);
    roll_brake.set_x(24);
    roll_brake.set_word(0xC004, 0x0200);
    roll_brake.set_byte(0xC015, 1);
    roll_brake.press(Key_Down);
    roll_brake.press(Key_Left);
    roll_brake.frames(3);
    assert(roll_brake.byte(0xC015) && roll_brake.vx() == 0x0200 - 3 * 4);
    roll_brake.release(Key_Down);
    roll_brake.frames(1);
    assert(!roll_brake.byte(0xC015) && roll_brake.vx() == 0x0200 - 3 * 4 - 0x30);
    Simulation low_speed(argv[1]);
    low_speed.set_word(0xC004, 0x0040);
    low_speed.press(Key_Down);
    low_speed.frames(1);
    assert(low_speed.byte(0xC015) && low_speed.vx() == 0x003c);
    Simulation tiny_speed(argv[1]);
    tiny_speed.set_word(0xC004, -3);
    tiny_speed.set_byte(0xC015, 1);
    tiny_speed.frames(1);
    assert(tiny_speed.vx() == 0 && !tiny_speed.byte(0xC015));

    // Set up rolls on both downward slopes; speed must not decrease.
    Simulation downhill_right(argv[1]);
    downhill_right.set_x(244); // centre in column 32, falling to the right
    downhill_right.set_y(136);
    downhill_right.set_word(0xC004, 0x0200);
    downhill_right.set_byte(0xC015, 1);
    downhill_right.frames(2);
    assert(downhill_right.vx() == 0x0200 && downhill_right.byte(0xC015));
    Simulation downhill_left(argv[1]);
    downhill_left.set_x(116); // centre in column 16, falling to the left
    downhill_left.set_y(136);
    downhill_left.set_word(0xC004, -0x0200);
    downhill_left.set_byte(0xC015, 1);
    downhill_left.frames(2);
    assert(downhill_left.vx() == -0x0200 && downhill_left.byte(0xC015));
    Simulation uphill(argv[1]);
    uphill.set_x(116);
    uphill.set_y(136);
    uphill.set_word(0xC004, 0x0200);
    uphill.set_byte(0xC015, 1);
    uphill.frames(2);
    assert(uphill.vx() < 0x0200 && uphill.byte(0xC015));
    uphill.press(Key_1);
    uphill.frames(2);
    assert(!uphill.grounded() && uphill.byte(0xC015) == 0);
    assert(uphill.sprite_y() == uphill.expected_sprite_y(0));
    // Check all short source frames in both facing directions, including the
    // alternate rolling frame 0C, through the animation viewer.
    Simulation short_frames(argv[1]);
    short_frames.press(Key_2);
    for (int facing = 0; facing < 2; ++facing) {
        short_frames.set_byte(0xC00B, facing);
        for (int frame = 7; frame <= 12; ++frame) {
            short_frames.set_byte(0xC010, frame);
            short_frames.frames(2);
            assert(short_frames.byte(0xC00D) == frame);
            assert(short_frames.sprite_y() == short_frames.expected_sprite_y(
                (frame == 8 || frame == 10) ? 9 : 8));
        }
    }
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
