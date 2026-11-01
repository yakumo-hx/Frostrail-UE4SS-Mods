"""Read public Lua C API RVAs from the pinned UE4SS PDB."""
import struct


def pdb_public_symbols(data: bytes, pe):
    """Read S_PUB32 records from the fixed loader's MSF 7 / DBI symbol stream."""
    u32 = lambda b, o: struct.unpack_from("<I", b, o)[0]
    block_size, directory_size, block_map = (u32(data, o) for o in (32, 44, 52))

    def blocks_at(buffer, offset, count):
        return struct.unpack_from("<" + "I" * count, buffer, offset)

    def join_blocks(blocks, size):
        return b"".join(data[b * block_size:(b + 1) * block_size] for b in blocks)[:size]

    directory = join_blocks(blocks_at(data, block_map * block_size,
                           (directory_size + block_size - 1) // block_size), directory_size)
    count = u32(directory, 0)
    sizes = blocks_at(directory, 4, count)
    cursor = 4 + count * 4
    streams = []
    for size in sizes:
        if size == 0xFFFFFFFF:
            streams.append(b"")
            continue
        block_count = (size + block_size - 1) // block_size
        streams.append(join_blocks(blocks_at(directory, cursor, block_count), size))
        cursor += block_count * 4
    symbols = streams[struct.unpack_from("<H", streams[3], 20)[0]]
    cursor = 0
    result = {}
    while cursor + 4 <= len(symbols):
        length, kind = struct.unpack_from("<HH", symbols, cursor)
        if length < 2:
            break
        if kind == 0x110E:
            _, offset, segment = struct.unpack_from("<IIH", symbols, cursor + 4)
            name = symbols[cursor + 14:cursor + 2 + length].split(b"\0")[0].decode("utf8", "replace")
            if name.startswith("lua_"):
                result[name] = pe.sections[segment - 1].VirtualAddress + offset
        cursor += length + 2
    return result
