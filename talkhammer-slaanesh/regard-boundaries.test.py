"""Run the real TalkHammer disposition.score against vanilla-attitude boundary cases."""
import struct
import sys
import os
from pathlib import Path
if os.environ.get('TWW3_LUPA_PATH'):
    sys.path.insert(0, os.environ['TWW3_LUPA_PATH'])
from lupa import LuaRuntime


def unpack(path):
    data = Path(path).read_bytes()
    assert data[:4] == b'PFH5'
    count, index_size = struct.unpack_from('<II', data, 16)
    index = 28 + struct.unpack_from('<I', data, 12)[0]
    offset = index + index_size
    entries = {}
    for _ in range(count):
        size, compressed = struct.unpack_from('<IB', data, index)
        end = data.index(0, index + 5)
        name = data[index+5:end].decode()
        entries[name] = (data[offset:offset+size], compressed)
        index = end + 1
        offset += size
    assert offset == len(data)
    return entries


def check(path):
    source, compressed = unpack(path)[r'script\talkhammer\lib\disposition.lua']
    assert not compressed
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('TALKHAMMER_U8 = {sub=string.sub, blen=string.len, clean=function(s) return s end, fold_typography=function(s) return s end}')
    disposition = lua.execute(source.decode())
    lua.globals().disposition = disposition
    evaluate = lua.eval('''function(raw)
        disposition.init({ world = {
            get = function() return {} end,
            attitude = function() return raw end,
        } })
        local snapshot = { treasury=1000, regions=1, wars={} }
        return disposition.score("test_them", "test_you", snapshot, snapshot, {v1=true})
    end''')
    for raw, expected in [(-1000,-40), (-100,-40), (-50,-20), (0,0), (50,20), (100,40), (200,80), (499,200), (500,200), (1000,200)]:
        score, reasons, parts = evaluate(raw)
        assert score == expected, f'vanilla {raw}: expected {expected}, got {score}'
    assert disposition.attitude_scale == 0.4
    assert disposition.regard_cap == 250
    print('Real Lua score: 10 attitude cases passed; lower cap -40, upper cap +200; scale .4 and overall cap 250 retained')


if __name__ == '__main__':
    check(sys.argv[1])
