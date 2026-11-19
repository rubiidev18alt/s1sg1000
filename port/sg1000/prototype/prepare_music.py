"""Compile two SMS song tone streams into a compact, simplified PSG score.

Loop counts, note lengths, direct volume and restart points are retained.
Envelope, vibrato, bend, legato and the discarded tone/noise channels are
not rendered. Only the two known, ROM-validated songs are used by the build.
"""
import struct


def decode(song, channel, numerator, denominator):
    if channel not in (0, 1):
        raise ValueError('only the first two tone channels are supported')
    offsets = struct.unpack_from('<4H', song)
    start, end = offsets[channel:channel + 2]
    if not 10 <= start < end <= len(song):
        raise ValueError('invalid channel range')
    pos = start
    volume, default = 0, 0
    stack = []
    result = []
    restart = None
    ticks = 0
    steps = 0

    def read(count):
        nonlocal pos
        if pos + count > end:
            raise ValueError('truncated music command')
        data = song[pos:pos + count]
        pos += count
        return data

    while steps < 10000:
        steps += 1
        command = read(1)[0]
        if command < 0x80:
            if 0x70 <= command < 0x7f or (command & 15) == 15 and command != 0x7f:
                raise ValueError('unsupported tone note')
            duration = read(1)[0] or default
            if not duration:
                raise ValueError('zero note duration')
            next_ticks = ticks + duration
            frames = (next_ticks * numerator // denominator -
                      ticks * numerator // denominator)
            if not 1 <= frames <= 255:
                raise ValueError('note duration out of range')
            result.append((frames, command, 15 if command == 0x7f else 15 - volume))
            ticks = next_ticks
        elif command == 0x80:
            mul, tempo = struct.unpack('<HH', read(4))
            if (mul, tempo) != (numerator, denominator):
                raise ValueError('unexpected song tempo')
        elif command == 0x81:
            volume = read(1)[0]
            if volume > 15:
                raise ValueError('invalid volume')
        elif command in (0x82, 0x83, 0x84, 0x85, 0x89):
            read({0x82: 6, 0x83: 5, 0x84: 2, 0x85: 1, 0x89: 1}[command])
        elif command == 0x86:
            stack.append(0)
        elif command == 0x87:
            count, lo, hi = read(3)
            target = lo | hi << 8
            if not stack or not count or not start <= target < end:
                raise ValueError('invalid music loop')
            if not stack[-1]:
                stack[-1] = count - 1
            else:
                stack[-1] -= 1
            if stack[-1]:
                pos = target
            else:
                stack.pop()
        elif command == 0x88:
            restart = len(result)
        elif command == 0x8a:
            default = read(1)[0]
        elif command == 0x8b:
            volume = min(15, volume + 1)
        elif command == 0x8c:
            volume = max(0, volume - 1)
        elif command == 0x8d:
            pass  # no envelope or legato in this arrangement
        elif command in (0xfe, 0xff):
            if stack or not result:
                raise ValueError('unfinished music loop or empty stream')
            return result, restart if command == 0xff else None
        else:
            raise ValueError('unsupported music command: {:02x}'.format(command))
    raise ValueError('music stream exceeds command limit')


def compile_score(songs):
    lines = []
    for name, tempo in [('title', (5, 4)), ('ghz', (1, 1))]:
        for channel in (0, 1):
            events, restart = decode(songs[name], channel, *tempo)
            label = 'music_{}_{}'.format(name, channel)
            lines.append(label + ':')
            for index, (duration, note, volume) in enumerate(events):
                if index == restart:
                    lines.append(label + '_loop:')
                lines.append('.db {}, {}, {}'.format(duration, note, volume))
            lines.append('.db 0')
            lines.append('.dw {}'.format(label + '_loop' if restart is not None else '0'))
    return '\n'.join(lines) + '\n'
