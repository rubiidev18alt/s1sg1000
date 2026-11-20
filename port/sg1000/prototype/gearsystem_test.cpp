// Optional integration test against a local Gearsystem source checkout.
#include "GearsystemCore.h"
#include "Memory.h"
#include "Audio.h"
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
    // Title plays on tone 0/1, with tone 2 kept free. Entering TEST
    // silences both music channels; entering GHZ starts its own arrangement.
    Simulation title_music(argv[1], false);
    auto title_state = title_music.core.GetAudio()->GetPSG()->GetState();
    for (int i = 0; i < 100 && title_state.channels[0].volume_reg == 15; ++i) {
        title_music.frames(1);
        title_state = title_music.core.GetAudio()->GetPSG()->GetState();
    }
    assert(title_state.channels[0].volume_reg < 15);
    assert(title_state.channels[0].period == 338 * 16);
    assert(title_state.channels[2].volume_reg == 15);
    int title_attack = title_state.channels[0].volume_reg;
    title_music.frames(4);
    assert(title_music.core.GetAudio()->GetPSG()->GetState().channels[0].volume_reg == title_attack + 2);
    title_music.press(Key_1);
    title_music.frames(2);
    title_music.release(Key_1);
    title_music.frames(10);
    auto test_state = title_music.core.GetAudio()->GetPSG()->GetState();
    assert(test_state.channels[0].volume_reg == 15);
    assert(test_state.channels[1].volume_reg == 15);
    assert(test_state.channels[3].volume_reg == 15);
    Simulation ghz_music(argv[1], false);
    ghz_music.press(Key_2);
    ghz_music.frames(3);
    ghz_music.release(Key_2);
    ghz_music.frames(2);
    ghz_music.press(Key_1);
    ghz_music.frames(3);
    ghz_music.release(Key_1);
    ghz_music.frames(40);
    auto ghz_state = ghz_music.core.GetAudio()->GetPSG()->GetState();
    assert(ghz_state.channels[0].volume_reg < 15);
    assert(ghz_state.channels[1].volume_reg < 15);
    assert(ghz_state.channels[2].volume_reg == 15);
    assert(ghz_state.channels[3].volume_reg < 15);
    assert(ghz_state.noise_white && ghz_state.noise_rate == 1);
    int noise_period = ghz_state.channels[3].period;
    ghz_music.press(Key_1);
    ghz_music.frames(3);
    ghz_state = ghz_music.core.GetAudio()->GetPSG()->GetState();
    assert(ghz_state.channels[0].volume_reg < 15);
    assert(ghz_state.channels[2].volume_reg < 15); // effects alongside music
    assert(ghz_state.noise_rate == 1 && ghz_state.channels[3].period == noise_period);
    ghz_music.release(Key_1);
    ghz_music.frames(3);
    ghz_music.press(Key_2);
    ghz_music.frames(3);
    ghz_music.release(Key_2);
    ghz_music.set_x(4096);
    ghz_music.set_y(200);
    ghz_music.frames(3);
    int debug_start = ghz_music.x();
    ghz_music.press(Key_Right);
    ghz_music.frames(120);
    ghz_music.release(Key_Right);
    int debug_updates = (ghz_music.x() - debug_start) / 4;
    std::printf("GHZ flight updates in 120 video frames: %d\n", debug_updates);
    assert(debug_updates >= 115);
    Simulation menu(argv[1], false);
    auto vram = menu.core.GetVideo()->GetVRAM();
    const u8 brand[] = {12, 21, 22, 23, 24, 0, 12, 16};
    for (int i = 0; i < 8; ++i) assert(vram[0x186C + i] == brand[i]);
    assert(vram[0x2003] == 0xF1); // lowercase c is white on black
    assert(vram[24 * 8 + 2] == 0x1C); // lowercase c glyph
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
    assert(vram[0x186C] != 12); // branding is removed on level entry
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
    assert(vram2[0x2008] == 0x32 && vram2[0x2009] == 0xA6); // grass and soil
    assert(vram2[0x2004] == 0xA7); // yellow rings and matching HUD icon
    const u8 grass_pattern[] = {0xFF, 0xFF, 0xAA, 0xAA, 0xAA, 0x44, 0x44, 0x44};
    for (int i = 0; i < 8; ++i) assert(vram2[0x200 + i] == grass_pattern[i]);
    int grass_tiles = 0;
    for (int i = 0; i < 768; ++i) grass_tiles += (vram2[0x1800 + i] == 64);
    assert(grass_tiles > 0);
    assert(button2.camera_x() == 21 && button2.camera_y() == 37);
    for (int i = 0; i < 32; ++i) {
        if (i < 2 || (i > 3 && i != 5 && i != 6))
            assert(vram2[0x1800 + i] == 0);      // sky outside HUD
        assert(vram2[0x1800 + 15 * 32 + i] == 72 + ((21 + i + 37 + 15) & 1)); // world-aligned checker
    }
    // Scrolling by one tile must not make the checkerboard swim.
    u8 fixed_world_tile = vram2[0x1800 + 15 * 32 + 10];
    button2.set_x(264);
    button2.frames(4);
    assert(button2.camera_x() == 22);
    assert(vram2[0x1800 + 15 * 32 + 9] == fixed_world_tile);
    button2.set_x(256);
    button2.frames(4);
    assert(button2.camera_x() == 21);
    // GHZ debug toggles once, flies through terrain, clamps to GHZ bounds,
    // and resumes normal gravity on exit. The viewer uses both buttons.
    button2.press(Key_2);
    button2.frames(5);
    assert(button2.byte(0xC03D) == 1);
    button2.release(Key_2);
    button2.frames(2);
    button2.set_x(6556);
    button2.set_y(476);
    button2.press(Key_Right);
    button2.press(Key_Down);
    button2.frames(4);
    assert(button2.x() == 6559 && button2.y() == 480);
    button2.release(Key_Right);
    button2.release(Key_Down);
    button2.set_x(2);
    button2.set_y(2);
    button2.press(Key_Left);
    button2.press(Key_Up);
    button2.frames(4);
    assert(button2.x() == 0 && button2.y() == 0);
    button2.release(Key_Left);
    button2.release(Key_Up);
    button2.set_x(256);
    button2.set_y(200);
    button2.press(Key_2);
    button2.frames(3);
    assert(button2.byte(0xC03D) == 0 && button2.y() > 200);
    button2.release(Key_2);
    button2.frames(3);
    button2.press(Key_1);
    button2.press(Key_2);
    button2.press(Key_Right);
    button2.frames(3);
    assert(button2.byte(0xC00D) == 1 && button2.x() == 256);
    assert(button2.byte(0xC03D) == 0);
    button2.release(Key_Right);
    button2.release(Key_1);
    button2.release(Key_2);
    button2.frames(3);
    // A real GHZ ring at (912,200) is rendered from the SMS metatile map.
    button2.set_x(880);
    button2.set_y(192);
    button2.set_word(0xC004, 0);
    button2.set_word(0xC006, 0);
    button2.set_byte(0xC008, 0);
    button2.frames(6);
    int cam_pixels = 8 * (button2.camera_x() + 256 * button2.byte(0xC01E));
    int sx = (912 - cam_pixels) / 8;
    int sy = (200 - button2.camera_y() * 8) / 8;
    assert(sx >= 0 && sx < 31 && sy >= 0 && sy < 23);
    assert(vram2[0x1800 + sy * 32 + sx] == 32);
    button2.set_x(900);
    button2.set_y(192);
    button2.set_word(0xC006, 0);
    button2.frames(4);
    assert(button2.byte(0xC03E) == 1);
    assert(vram2[0x1805] == 40 && vram2[0x1806] == 42);
    button2.frames(10);
    assert(button2.byte(0xC03E) == 1); // already collected
    cam_pixels = 8 * (button2.camera_x() + 256 * button2.byte(0xC01E));
    sx = (912 - cam_pixels) / 8;
    sy = (200 - button2.camera_y() * 8) / 8;
    assert(vram2[0x1800 + sy * 32 + sx] == 0); // erased from map
    // The detached row-9 platform stays one-way. Start below its bottom,
    // pass through from below, then land on top.
    button2.set_x(900);
    button2.set_y(322);
    button2.set_word(0xC006, 0xFC80);
    button2.set_byte(0xC008, 0);
    button2.set_byte(0xC009, 16);
    button2.set_byte(0xC00A, 1);
    button2.press(Key_1);
    int min_y = 1000;
    bool passed_upward = false;
    for (int i = 0; i < 150; ++i) {
        if (i == 16) button2.release(Key_1);
        button2.frames(1);
        if (button2.y() < min_y) min_y = button2.y();
        passed_upward |= button2.y() < 272 && !button2.grounded();
    }
    assert(passed_upward && min_y < 272);
    assert(button2.y() == 272 && button2.grounded());
    // This sloped floor is part of the ground, despite empty space below.
    // Its underside at y=384 must stop Sonic when jumping from below.
    button2.set_x(450);
    button2.set_y(386);
    button2.set_word(0xC004, 0);
    button2.set_word(0xC006, 0xFC80);
    button2.set_byte(0xC008, 0);
    button2.frames(4);
    assert(button2.y() >= 384 && static_cast<short>(button2.word(0xC006)) >= 0);
    // A flat floor connected to terrain also has a solid underside, even
    // when the metatile directly below it is empty.
    button2.set_x(4132);
    button2.set_y(386);
    button2.set_word(0xC004, 0);
    button2.set_word(0xC006, 0xFC80);
    button2.set_byte(0xC008, 0);
    button2.frames(4);
    assert(button2.y() >= 384 && static_cast<short>(button2.word(0xC006)) >= 0);
    // The centre can be off a platform while a foot still overlaps it.
    // At row 9 the platform ends at x=992; x=981 has a foot over it.
    button2.set_x(981);
    button2.set_y(260);
    button2.set_word(0xC004, 0);
    button2.set_word(0xC006, 0);
    button2.set_byte(0xC008, 0);
    button2.frames(60);
    assert(button2.y() == 272 && button2.grounded());
    // Also test the right foot at the opposite platform edge, x=896.
    button2.set_x(878);
    button2.set_y(260);
    button2.set_word(0xC006, 0);
    button2.set_byte(0xC008, 0);
    button2.frames(60);
    assert(button2.y() == 272 && button2.grounded());
    // With both feet beyond the edge, Sonic must still fall.
    button2.set_x(993);
    button2.set_y(260);
    button2.set_word(0xC006, 0);
    button2.set_byte(0xC008, 0);
    button2.frames(45);
    assert(button2.y() > 272);
    // A shallow overlap with a solid wall must not slip past the probes.
    button2.set_x(454);
    button2.set_y(357);
    button2.set_word(0xC004, 0x0300);
    button2.set_word(0xC006, 0);
    button2.set_byte(0xC008, 0);
    button2.press(Key_Right);
    button2.frames(2);
    assert(button2.x() == 456 && button2.vx() == 0);
    button2.release(Key_Right);
    button2.frames(3);
    // Profile 22 is a solid block: it stops side and underside crossings.
    // Row 12, column 15 is solid, with empty space immediately to its left.
    button2.set_x(454);
    button2.set_y(384);
    button2.set_word(0xC004, 0x0300);
    button2.set_word(0xC006, 0);
    button2.set_byte(0xC008, 0);
    button2.press(Key_Right);
    button2.frames(4);
    assert(button2.x() == 456 && button2.vx() == 0);
    button2.release(Key_Right);
    button2.frames(3);
    // Row 12, column 24 ends at x=800 with empty space to its right.
    button2.set_x(802);
    button2.set_y(384);
    button2.set_word(0xC004, 0xFD00);
    button2.set_word(0xC006, 0);
    button2.set_byte(0xC008, 0);
    button2.press(Key_Left);
    button2.frames(4);
    assert(button2.x() == 800 && button2.vx() == 0);
    button2.release(Key_Left);
    button2.frames(3);
    // Row 13 at the starting x has a solid underside at y=448.
    button2.set_x(256);
    button2.set_y(450);
    button2.set_word(0xC004, 0);
    button2.set_word(0xC006, 0xFC80);
    button2.set_byte(0xC008, 0);
    button2.frames(4);
    assert(button2.y() >= 448 && static_cast<short>(button2.word(0xC006)) >= 0);
    // The leftmost three sprite pixels overlap a solid ceiling; neither
    // inset ceiling probe should be able to miss that overlap.
    button2.set_x(797);
    button2.set_y(418);
    button2.set_word(0xC004, 0);
    button2.set_word(0xC006, 0xFC80);
    button2.set_byte(0xC008, 0);
    button2.frames(3);
    assert(button2.y() >= 416 && static_cast<short>(button2.word(0xC006)) >= 0);
    // Return to the start platform for the movement rate measurement.
    button2.set_x(256);
    button2.set_y(368);
    button2.set_word(0xC004, 0);
    button2.set_word(0xC006, 0);
    button2.set_byte(0xC008, 1);
    button2.frames(5);
    int ghz_tick_before = button2.byte(0xC00C);
    button2.press(Key_Right);
    button2.frames(120);
    int ghz_ticks = (button2.byte(0xC00C) - ghz_tick_before) & 255;
    std::printf("GHZ updates in 120 video frames: %d\n", ghz_ticks);
    assert(ghz_ticks >= 115);
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
    assert(button2.byte(0xC03E) == 0); // reset level resets rings
    Simulation test_ring(argv[1]);
    auto ring_vram = test_ring.core.GetVideo()->GetVRAM();
    assert(ring_vram[0x2004] == 0xA1); // rings and HUD icon share yellow group
    assert(ring_vram[0x1802] == 36 && ring_vram[0x1803] == 38);
    std::vector<u8> first_ring(ring_vram + 0x100, ring_vram + 0x120);
    test_ring.frames(8);
    bool changed = false;
    for (int i = 0; i < 32; ++i) changed |= first_ring[i] != ring_vram[0x100 + i];
    assert(changed);
    test_ring.frames(40);
    for (int i = 0; i < 32; ++i) assert(first_ring[i] == ring_vram[0x100 + i]);
    assert(test_ring.byte(0xC03E) == 0);
    assert(ring_vram[0x1800 + 9 * 32 + 12] == 32); // ring at 96,176
    test_ring.set_x(84);
    test_ring.set_y(176);
    test_ring.frames(6);
    assert(test_ring.byte(0xC03E) == 1);
    auto ring_audio = test_ring.core.GetAudio()->GetPSG()->GetState();
    assert(ring_audio.channels[2].volume_reg == 0);
    assert(ring_audio.channels[2].period == 71 * 16);
    for (int channel : {0, 1, 3}) assert(ring_audio.channels[channel].volume_reg == 15);
    assert(ring_vram[0x1805] == 40 && ring_vram[0x1806] == 42);
    test_ring.frames(10);
    ring_audio = test_ring.core.GetAudio()->GetPSG()->GetState();
    assert(ring_audio.channels[2].period == 53 * 16);
    assert(ring_audio.channels[2].volume_reg == 2);
    test_ring.frames(10);
    assert(test_ring.core.GetAudio()->GetPSG()->GetState().channels[2].volume_reg == 15);
    assert(test_ring.byte(0xC03E) == 1);
    Simulation wrap_ring(argv[1]);
    wrap_ring.set_byte(0xC03E, 0x99);
    wrap_ring.set_x(84);
    wrap_ring.set_y(176);
    wrap_ring.frames(6);
    assert(wrap_ring.byte(0xC03E) == 0); // SMS BCD counter wraps at 100
    // Sound effects occupy only PSG tone 2. TEST has no background music.
    Simulation sound(argv[1]);
    auto psg = sound.core.GetAudio()->GetPSG();
    auto state = psg->GetState();
    for (int channel = 0; channel < 4; ++channel)
        assert(state.channels[channel].volume_reg == 15);
    sound.press(Key_1);
    sound.frames(1);
    state = psg->GetState();
    assert(state.channels[2].volume_reg < 15);
    assert(state.channels[2].period == 320 * 16); // SMS jump's first pitch
    for (int channel : {0, 1, 3}) assert(state.channels[channel].volume_reg == 15);
    sound.frames(5);
    state = psg->GetState();
    assert(state.channels[2].period == 239 * 16);
    sound.frames(1);
    assert(psg->GetState().channels[2].period == 231 * 16); // vibrato bend
    sound.release(Key_1);
    sound.frames(30);
    assert(psg->GetState().channels[2].volume_reg == 15);
    Simulation sound_roll(argv[1]);
    sound_roll.set_word(0xC004, 0x0200);
    sound_roll.press(Key_Down);
    sound_roll.frames(1);
    assert(sound_roll.core.GetAudio()->GetPSG()->GetState().channels[2].period == 56 * 16);
    sound_roll.release(Key_Down);
    sound_roll.set_word(0xC004, 0); // avoid collecting rings during the long sweep
    sound_roll.frames(20);
    auto roll_state = sound_roll.core.GetAudio()->GetPSG()->GetState();
    assert(roll_state.channels[2].period < 56 * 16);
    assert(roll_state.channels[2].volume_reg == 4);
    sound_roll.frames(150);
    assert(sound_roll.core.GetAudio()->GetPSG()->GetState().channels[2].volume_reg == 15);
    Simulation sound_brake(argv[1]);
    sound_brake.set_word(0xC004, 0x0200);
    sound_brake.press(Key_Left);
    sound_brake.frames(1);
    assert(sound_brake.core.GetAudio()->GetPSG()->GetState().channels[2].period == 134 * 16);
    sound_brake.frames(4);
    assert(sound_brake.core.GetAudio()->GetPSG()->GetState().channels[2].volume_reg == 15);
    sound_brake.frames(2);
    assert(sound_brake.core.GetAudio()->GetPSG()->GetState().channels[2].volume_reg == 0);
    sound_brake.frames(25);
    assert(sound_brake.core.GetAudio()->GetPSG()->GetState().channels[2].volume_reg == 15);
    // Stable sprites and HUD no longer upload identical tiles every frame.
    // A new frame or counter value must still invalidate its own cache.
    Simulation cache(argv[1]);
    auto cache_vram = cache.core.GetVideo()->GetVRAM();
    const u8 old_pattern = cache_vram[0x3800];
    cache_vram[0x3800] = old_pattern ^ 0xff;
    cache_vram[0x1802] = 0x7e;
    cache.frames(2);
    assert(cache_vram[0x3800] == (old_pattern ^ 0xff));
    assert(cache_vram[0x1802] == 0x7e);
    cache.set_byte(0xC03E, 1);
    cache.frames(1);
    assert(cache_vram[0x1802] == 36 && cache_vram[0x1806] == 42);
    cache.press(Key_1);
    cache.frames(3);
    assert(cache_vram[0x3800] != (old_pattern ^ 0xff));
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
    Simulation powered_right(argv[1]);
    powered_right.set_x(244);
    powered_right.set_y(136);
    powered_right.set_word(0xC004, 0x0200);
    powered_right.set_byte(0xC015, 1);
    powered_right.press(Key_Down);
    powered_right.press(Key_Right);
    powered_right.frames(2);
    assert(powered_right.vx() > 0x0200);
    Simulation up_powered_right(argv[1]);
    up_powered_right.set_x(244); up_powered_right.set_y(136);
    up_powered_right.set_word(0xC004, 0x0200); up_powered_right.set_byte(0xC015, 1);
    up_powered_right.press(Key_Up); up_powered_right.press(Key_Right);
    up_powered_right.frames(2);
    assert(up_powered_right.vx() > 0x0200 && up_powered_right.byte(0xC015));
    Simulation downhill_left(argv[1]);
    downhill_left.set_x(116); // centre in column 16, falling to the left
    downhill_left.set_y(136);
    downhill_left.set_word(0xC004, -0x0200);
    downhill_left.set_byte(0xC015, 1);
    downhill_left.frames(2);
    assert(downhill_left.vx() == -0x0200 && downhill_left.byte(0xC015));
    Simulation ghz_roll(argv[1], false);
    ghz_roll.press(Key_2); ghz_roll.frames(3); ghz_roll.release(Key_2); ghz_roll.frames(2);
    ghz_roll.press(Key_1); ghz_roll.frames(3); ghz_roll.release(Key_1); ghz_roll.frames(40);
    ghz_roll.set_x(2100); ghz_roll.set_y(252);
    ghz_roll.set_word(0xC004, 0x0200); ghz_roll.set_word(0xC006, 0);
    ghz_roll.set_byte(0xC008, 1); ghz_roll.set_byte(0xC015, 1);
    ghz_roll.press(Key_Right); ghz_roll.press(Key_Up);
    ghz_roll.frames(10);
    assert(ghz_roll.vx() > 0x0200); // original GHZ downhill profile
    // GHZ1's SMS special-02 ramp at (2272,416). The requested up+right
    // input launches only with enough speed, preserving momentum and sound.
    Simulation ramp(argv[1], false);
    ramp.press(Key_2); ramp.frames(3); ramp.release(Key_2); ramp.frames(2);
    ramp.press(Key_1); ramp.frames(3); ramp.release(Key_1); ramp.frames(40);
    ramp.set_byte(0xC03D, 1); // hold position while the camera redraws
    ramp.set_x(2260); ramp.set_y(400); ramp.frames(20);
    auto ramp_vram = ramp.core.GetVideo()->GetVRAM();
    assert(ramp_vram[0x200A] == 0xF7);
    int ramp_art_tiles = 0;
    for (int i = 0; i < 768; ++i)
        ramp_art_tiles += (ramp_vram[0x1800 + i] >= 80 && ramp_vram[0x1800 + i] <= 87);
    assert(ramp_art_tiles == 8);
    const int ramp_cells[8][3] = {{287,53,87}, {284,54,80}, {285,54,82},
                                  {287,54,86}, {284,55,81}, {285,55,83},
                                  {286,55,84}, {287,55,85}};
    int ramp_cam_x = ramp.camera_x() + 256 * ramp.byte(0xC01E);
    for (auto &cell : ramp_cells) {
        int sx = cell[0] - ramp_cam_x, sy = cell[1] - ramp.camera_y();
        assert(sx >= 0 && sx < 32 && sy >= 0 && sy < 24);
        assert(ramp_vram[0x1800 + sy * 32 + sx] == cell[2]);
    }
    ramp.set_byte(0xC03D, 0);
    ramp.set_x(2271); ramp.set_y(410);
    ramp.set_word(0xC004, 0x0200); ramp.set_word(0xC006, 0);
    ramp.set_byte(0xC008, 1); ramp.set_byte(0xC015, 1);
    ramp.press(Key_Right); ramp.press(Key_Up); ramp.frames(2);
    assert(ramp.byte(0xC073) == 0); // too slow
    ramp.release(Key_Up); ramp.frames(2);
    ramp.set_x(2271); ramp.set_y(410);
    ramp.set_word(0xC004, 0x0BFC); ramp.set_word(0xC006, 0);
    ramp.set_byte(0xC008, 1); ramp.set_byte(0xC015, 1);
    ramp.frames(2);
    assert(ramp.byte(0xC073) == 0); // no up input
    ramp.set_x(2271); ramp.set_y(410);
    ramp.set_word(0xC004, 0x0BFC); ramp.set_word(0xC006, 0);
    ramp.set_byte(0xC008, 1); ramp.set_byte(0xC015, 1);
    ramp.set_byte(0xC013, 16); ramp.set_byte(0xC01E, 1); ramp.set_byte(0xC014, 40);
    ramp.press(Key_Right); ramp.press(Key_Up);
    for (int i = 0; i < 12 && ramp.byte(0xC073) == 0; ++i) ramp.frames(1);
    assert(ramp.byte(0xC073) == 1 && !ramp.grounded());
    assert(static_cast<short>(ramp.word(0xC006)) < -0x0E00);
    assert(ramp.vx() > 0x0B00);
    bool heard_launch = false;
    for (int i = 0; i < 12 && !heard_launch; ++i) {
        ramp.frames(1);
        heard_launch = ramp.core.GetAudio()->GetPSG()->GetState().channels[2].volume_reg < 15;
    }
    assert(heard_launch);
    assert(ramp.byte(0xC074) == 1);
    auto during_launch = ramp.core.GetAudio()->GetPSG()->GetState();
    assert(during_launch.channels[2].volume_reg <= 1); // louder ramp attack
    int cam_before = ramp.camera_x() + 256 * ramp.byte(0xC01E);
    int cam_y_before = ramp.camera_y();
    int ticks_before = ramp.byte(0xC00C);
    int x_before = ramp.x();
    ramp.frames(20);
    int cam_after = ramp.camera_x() + 256 * ramp.byte(0xC01E);
    int updates = (ramp.byte(0xC00C) - ticks_before) & 255;
    assert(updates > 0);
    assert(cam_after - cam_before <= updates); // at most 8 px per update
    assert(cam_y_before - ramp.camera_y() <= updates);
    assert(ramp.x() - x_before > (cam_after - cam_before) * 8);
    // A high launch must not wrap above y=0 and be mistaken for a fall
    // below the level. Offscreen Sonic must not wrap around the sprite X.
    ramp.set_x(3000); ramp.set_y(4);
    ramp.set_word(0xC006, -0x0800);
    ramp.set_byte(0xC008, 0); ramp.set_byte(0xC073, 1);
    ramp.set_byte(0xC013, 0); ramp.set_byte(0xC01E, 0); ramp.set_byte(0xC014, 0);
    ramp.frames(40);
    assert(ramp.byte(0xC012) == 0 && ramp.x() >= 3000);
    assert(ramp.sprite_y() == 0xD0); // still far beyond the trailing camera
    // Run down the actual approach instead of teleporting onto the launch lip.
    Simulation approach(argv[1], false);
    approach.press(Key_2); approach.frames(3); approach.release(Key_2); approach.frames(2);
    approach.press(Key_1); approach.frames(3); approach.release(Key_1); approach.frames(40);
    approach.set_x(2100); approach.set_y(240);
    approach.set_word(0xC004, 0x0300); approach.set_word(0xC006, 0);
    approach.set_byte(0xC008, 1); approach.set_byte(0xC015, 0);
    approach.press(Key_Right); approach.press(Key_Down);
    for (int i = 0; i < 12 && !approach.byte(0xC015); ++i) approach.frames(1);
    assert(approach.byte(0xC015));
    approach.release(Key_Down); approach.press(Key_Up);
    for (int i = 0; i < 240 && approach.x() < 2250; ++i) approach.frames(1);
    assert(approach.x() >= 2250 && approach.vx() > 0x0300);
    for (int i = 0; i < 100 && approach.byte(0xC073) == 0 && approach.x() < 2320; ++i)
        approach.frames(1);
    assert(approach.byte(0xC073) == 1);
    // Ring collection cannot interrupt the ramp effect, but the song keeps
    // advancing and sounding on its own channels throughout.
    Simulation priority(argv[1], false);
    priority.press(Key_2); priority.frames(3); priority.release(Key_2); priority.frames(2);
    priority.press(Key_1); priority.frames(3); priority.release(Key_1); priority.frames(40);
    priority.set_byte(0xC03D, 1);
    priority.set_x(2260); priority.set_y(400); priority.frames(20);
    priority.set_byte(0xC03D, 0);
    priority.set_x(2271); priority.set_y(410);
    priority.set_word(0xC004, 0x0BFC); priority.set_word(0xC006, 0);
    priority.set_byte(0xC008, 1); priority.set_byte(0xC015, 1);
    priority.press(Key_Right); priority.press(Key_Up);
    for (int i = 0; i < 30 && priority.byte(0xC074) == 0; ++i) priority.frames(1);
    assert(priority.byte(0xC074) == 1);
    int saved_song0 = priority.word(0xC05B), saved_song1 = priority.word(0xC062);
    int saved_noise_ptr = priority.word(0xC069);
    int launch_ptr = priority.word(0xC058);
    priority.set_byte(0xC03D, 1);
    priority.release(Key_Right); priority.release(Key_Up);
    priority.set_x(2292); priority.set_y(312);
    for (int i = 0; i < 30 && priority.byte(0xC03E) == 0; ++i) priority.frames(1);
    assert(priority.byte(0xC03E) == 1); // ring collected during launch
    assert(priority.byte(0xC074) == 1);
    assert(priority.word(0xC058) >= launch_ptr); // still the launch effect
    bool music_advanced = false, music_audible = false;
    for (int i = 0; i < 180 && priority.byte(0xC074) != 0; ++i) {
        priority.frames(1);
        music_advanced |= priority.word(0xC05B) != saved_song0 ||
                          priority.word(0xC062) != saved_song1 ||
                          priority.word(0xC069) != saved_noise_ptr;
        auto psg = priority.core.GetAudio()->GetPSG()->GetState();
        music_audible |= psg.channels[0].volume_reg < 15 ||
                         psg.channels[1].volume_reg < 15 ||
                         psg.channels[3].volume_reg < 15;
    }
    assert(priority.byte(0xC074) == 0);
    assert(music_advanced && music_audible);
    priority.set_x(2308); priority.set_y(312);
    for (int i = 0; i < 30 && priority.byte(0xC03E) < 2; ++i) priority.frames(1);
    assert(priority.byte(0xC03E) >= 2);
    bool ring_after_launch = false;
    for (int i = 0; i < 20 && !ring_after_launch; ++i) {
        priority.frames(1);
        auto psg = priority.core.GetAudio()->GetPSG()->GetState();
        ring_after_launch = psg.channels[2].period == 84 * 16 && psg.channels[2].volume_reg < 15;
    }
    assert(ring_after_launch);
    Simulation flat_roll(argv[1]);
    flat_roll.set_word(0xC004, 0x0200); flat_roll.set_byte(0xC015, 1);
    flat_roll.press(Key_Right); flat_roll.press(Key_Up);
    flat_roll.frames(2);
    assert(flat_roll.vx() < 0x0200); // no boost on flat ground
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
    short_frames.press(Key_1);
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
    viewer.press(Key_1);
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
    viewer.release(Key_1);
    viewer.release(Key_2);
    viewer.frames(20);
    assert(viewer.x() > 24);
    // TEST button 2 toggles free flight once per press; terrain and gravity
    // are ignored, but the world bounds and camera still apply.
    Simulation debug(argv[1]);
    assert(debug.byte(0xC03D) == 0);
    debug.press(Key_2);
    debug.frames(10);
    assert(debug.byte(0xC03D) == 1 && debug.x() == 24 && debug.y() == 176);
    debug.release(Key_2);
    debug.frames(2);
    debug.press(Key_Right);
    debug.press(Key_Up);
    debug.frames(10);
    assert(debug.x() == 64 && debug.y() == 136);
    debug.release(Key_Right);
    debug.release(Key_Up);
    debug.frames(10);
    assert(debug.x() == 64 && debug.y() == 136); // no inertia/gravity
    debug.press(Key_Up);
    debug.frames(40);
    debug.release(Key_Up);
    assert(debug.y() == 0);
    debug.press(Key_Down);
    debug.frames(100);
    debug.release(Key_Down);
    assert(debug.y() == 352); // can fly through floor, clamped to map
    assert(debug.camera_y() == 24);
    debug.press(Key_Left);
    debug.frames(30);
    debug.release(Key_Left);
    assert(debug.x() == 0 && debug.camera_x() == 0);
    debug.set_x(740);
    debug.press(Key_Right);
    debug.frames(10);
    debug.release(Key_Right);
    assert(debug.x() == 744 && debug.camera_x() == 64);
    debug.set_x(24);
    debug.set_y(120);
    debug.press(Key_2);
    debug.frames(10);
    assert(debug.byte(0xC03D) == 0); // hold does not re-toggle
    assert(debug.y() > 120);           // normal gravity resumed
    debug.release(Key_2);
    debug.frames(60);
    assert(debug.y() == 176 && debug.grounded());
    debug.press(Key_2);
    debug.frames(2);
    debug.release(Key_2);
    debug.press(Key_Down);
    debug.frames(20);
    debug.release(Key_Down);
    assert(debug.y() > 176);
    debug.press(Key_2);
    debug.frames(2);
    debug.release(Key_2);
    debug.frames(3);
    assert(debug.y() == 176 && debug.grounded()); // safely resolves overlap
    std::puts("Gearsystem SG-1000 physics smoke tests passed");
}
