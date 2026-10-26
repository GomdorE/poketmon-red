import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDirectory, "..");
const sourceRoot = path.resolve(process.argv[2] ?? path.join(projectRoot, "..", "pokered-master"));
const outputDirectory = path.join(projectRoot, "assets", "maps");

const mapWidthBlocks = 10;
const mapHeightBlocks = 9;
const tilesPerBlockSide = 4;
const tileSize = 8;
const mapPath = path.join(sourceRoot, "maps", "PalletTown.blk");
const blocksetPath = path.join(sourceRoot, "gfx", "blocksets", "overworld.bst");
const tilesetPath = path.join(sourceRoot, "gfx", "tilesets", "overworld.2bpp");
const objectsPath = path.join(sourceRoot, "data", "maps", "objects", "PalletTown.asm");

const sourceFiles = [mapPath, blocksetPath, tilesetPath, objectsPath];
for (const sourceFile of sourceFiles) {
  if (!fs.existsSync(sourceFile)) {
    throw new Error(`Missing source file: ${sourceFile}`);
  }
}

const mapBlocks = fs.readFileSync(mapPath);
const blockset = fs.readFileSync(blocksetPath);
const tileset = fs.readFileSync(tilesetPath);
const objectsSource = fs.readFileSync(objectsPath, "utf8");

if (mapBlocks.length !== mapWidthBlocks * mapHeightBlocks) {
  throw new Error(`PalletTown.blk must contain 90 blocks, found ${mapBlocks.length}`);
}
if (blockset.length % 16 !== 0) {
  throw new Error("Overworld blockset size is not divisible by 16 tiles per block");
}
if (tileset.length % 16 !== 0) {
  throw new Error("Overworld tileset size is not divisible by 16 bytes per tile");
}

const palette = [
  [224, 248, 208, 255],
  [136, 192, 112, 255],
  [52, 104, 86, 255],
  [8, 24, 32, 255],
];
const tileCount = tileset.length / 16;
const pixelWidth = mapWidthBlocks * tilesPerBlockSide * tileSize;
const pixelHeight = mapHeightBlocks * tilesPerBlockSide * tileSize;
const pixels = Buffer.alloc(pixelWidth * pixelHeight * 4);

for (let blockY = 0; blockY < mapHeightBlocks; blockY += 1) {
  for (let blockX = 0; blockX < mapWidthBlocks; blockX += 1) {
    const blockId = mapBlocks[blockY * mapWidthBlocks + blockX];
    const blockOffset = blockId * 16;
    if (blockOffset + 16 > blockset.length) {
      throw new Error(`Block ${blockId} is outside the overworld blockset`);
    }

    for (let tileY = 0; tileY < tilesPerBlockSide; tileY += 1) {
      for (let tileX = 0; tileX < tilesPerBlockSide; tileX += 1) {
        const tileId = blockset[blockOffset + tileY * tilesPerBlockSide + tileX];
        if (tileId >= tileCount) {
          throw new Error(`Tile ${tileId} is outside the ${tileCount}-tile overworld tileset`);
        }
        drawTile(tileId, blockX * 32 + tileX * 8, blockY * 32 + tileY * 8);
      }
    }
  }
}

function drawTile(tileId, destinationX, destinationY) {
  const tileOffset = tileId * 16;
  for (let row = 0; row < 8; row += 1) {
    const lowPlane = tileset[tileOffset + row * 2];
    const highPlane = tileset[tileOffset + row * 2 + 1];
    for (let column = 0; column < 8; column += 1) {
      const bit = 7 - column;
      const colorIndex = ((highPlane >> bit) & 1) * 2 + ((lowPlane >> bit) & 1);
      const destination = ((destinationY + row) * pixelWidth + destinationX + column) * 4;
      pixels.set(palette[colorIndex], destination);
    }
  }
}

function parseEvents(pattern, mapper) {
  return [...objectsSource.matchAll(pattern)].map(mapper);
}

const borderMatch = objectsSource.match(/^\s*db\s+\$([0-9a-f]+)\s*;\s*border block/im);
const warps = parseEvents(
  /^\s*warp_event\s+(\d+),\s*(\d+),\s*([A-Z0-9_]+),\s*(\d+)/gim,
  (match) => ({ x: Number(match[1]), y: Number(match[2]), destination: match[3], destination_warp: Number(match[4]) }),
);
const backgroundEvents = parseEvents(
  /^\s*bg_event\s+(\d+),\s*(\d+),\s*([A-Z0-9_]+)/gim,
  (match) => ({ x: Number(match[1]), y: Number(match[2]), text: match[3] }),
);
const objects = parseEvents(
  /^\s*object_event\s+(\d+),\s*(\d+),\s*([A-Z0-9_]+),\s*([A-Z0-9_]+),\s*([A-Z0-9_]+),\s*([A-Z0-9_]+)/gim,
  (match) => ({ x: Number(match[1]), y: Number(match[2]), sprite: match[3], movement: match[4], direction: match[5], text: match[6] }),
);

const sha256 = (buffer) => crypto.createHash("sha256").update(buffer).digest("hex");
const metadata = {
  map_name: "태초마을",
  source_map: "PalletTown",
  tileset: "Overworld",
  width_blocks: mapWidthBlocks,
  height_blocks: mapHeightBlocks,
  width_pixels: pixelWidth,
  height_pixels: pixelHeight,
  block_size_pixels: tilesPerBlockSide * tileSize,
  border_block: borderMatch ? Number.parseInt(borderMatch[1], 16) : null,
  warps,
  background_events: backgroundEvents,
  objects,
  source_sha256: {
    map: sha256(mapBlocks),
    blockset: sha256(blockset),
    tileset: sha256(tileset),
    objects: sha256(Buffer.from(objectsSource)),
  },
};

const crcTable = Array.from({ length: 256 }, (_, value) => {
  let entry = value;
  for (let bit = 0; bit < 8; bit += 1) {
    entry = (entry & 1) ? (0xedb88320 ^ (entry >>> 1)) : (entry >>> 1);
  }
  return entry >>> 0;
});

fs.mkdirSync(outputDirectory, { recursive: true });
fs.writeFileSync(path.join(outputDirectory, "pallet_town.png"), encodePng(pixelWidth, pixelHeight, pixels));
fs.writeFileSync(path.join(outputDirectory, "pallet_town.json"), `${JSON.stringify(metadata, null, 2)}\n`);

console.log(`PALLET_TOWN_IMPORTED blocks=${mapBlocks.length} pixels=${pixelWidth}x${pixelHeight} warps=${warps.length} objects=${objects.length}`);

function encodePng(width, height, rgbaPixels) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  header[10] = 0;
  header[11] = 0;
  header[12] = 0;

  const scanlines = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y += 1) {
    const scanlineOffset = y * (width * 4 + 1);
    scanlines[scanlineOffset] = 0;
    rgbaPixels.copy(scanlines, scanlineOffset + 1, y * width * 4, (y + 1) * width * 4);
  }

  return Buffer.concat([
    signature,
    pngChunk("IHDR", header),
    pngChunk("IDAT", zlib.deflateSync(scanlines, { level: 9 })),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

function pngChunk(type, data) {
  const typeBytes = Buffer.from(type, "ascii");
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBytes, data])), 0);
  return Buffer.concat([length, typeBytes, data, crc]);
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

