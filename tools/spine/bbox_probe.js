// 打印每个动画在骨骼坐标里的包围盒（y 向上，原点是骨骼根）
const fs = require("fs"), path = require("path");
const spine = new Function(fs.readFileSync(path.join(__dirname, "spine-core-3.8.js"), "utf8") + "\nreturn spine;")();
const [skel, atlasPath] = process.argv.slice(2);
const atlasText = fs.readFileSync(atlasPath, "utf8");
class Tex extends spine.Texture { constructor() { super({ width: 516, height: 516 }); } setFilters() {} setWraps() {} dispose() {} }
const atlas = new spine.TextureAtlas(atlasText, () => new Tex());
const data = new spine.SkeletonBinary(new spine.AtlasAttachmentLoader(atlas)).readSkeletonData(new Uint8Array(fs.readFileSync(skel)));
const sk = new spine.Skeleton(data);
const verts = new Float32Array(4096);
for (const anim of data.animations) {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  const n = Math.max(1, Math.round(anim.duration * 30));
  for (let i = 0; i < n; i++) {
    sk.setToSetupPose(); const t = anim.duration * i / n;
    anim.apply(sk, t, t, true, null, 1, spine.MixBlend.setup, spine.MixDirection.mixIn); sk.updateWorldTransform();
    for (const slot of sk.drawOrder) {
      const a = slot.getAttachment(); let c = 0;
      if (a instanceof spine.RegionAttachment) { a.computeWorldVertices(slot.bone, verts, 0, 2); c = 8; }
      else if (a instanceof spine.MeshAttachment) { a.computeWorldVertices(slot, 0, a.worldVerticesLength, verts, 0, 2); c = a.worldVerticesLength; }
      for (let k = 0; k < c; k += 2) { minX = Math.min(minX, verts[k]); maxX = Math.max(maxX, verts[k]); minY = Math.min(minY, verts[k + 1]); maxY = Math.max(maxY, verts[k + 1]); }
    }
  }
  console.log(`${anim.name.padEnd(9)} x ${minX.toFixed(0)}..${maxX.toFixed(0)}  y ${minY.toFixed(0)}..${maxY.toFixed(0)}  (高 ${(maxY - minY).toFixed(0)})`);
}
