const sharp = require('sharp');
const path = require('path');

async function refineIcon() {
    const inputPath = path.resolve(__dirname, '..', 'www', 'icon_original.png');
    const outputPath = path.resolve(__dirname, '..', 'www', 'icon.png');

    // 1. 获取图片数据进行边界分析
    const { data, info } = await sharp(inputPath).raw().toBuffer({ resolveWithObject: true });
    const { width, height, channels } = info;
    const threshold = 40; // 提高阈值以忽略极暗的杂色

    let top = height, bottom = 0, left = width, right = 0;

    for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
            const idx = (y * width + x) * channels;
            if (data[idx] > threshold || data[idx+1] > threshold || data[idx+2] > threshold) {
                if (y < top) top = y;
                if (y > bottom) bottom = y;
                if (x < left) left = x;
                if (x > right) right = x;
            }
        }
    }

    // 稍微向内收缩 2 像素，确保完全没有黑边
    top += 2; bottom -= 2; left += 2; right -= 2;

    const cropW = right - left + 1;
    const cropH = bottom - top + 1;
    const size = Math.max(cropW, cropH);

    console.log(`精准裁切范围: ${cropW}x${cropH}, 最终输出大小: 1024x1024 (带透明圆角)`);

    // 2. 创建圆角遮罩
    // Android/iOS 图标通常使用 17% - 22% 的圆角半径
    const cornerRadius = Math.round(1024 * 0.18); 
    const roundedCornersMask = Buffer.from(
        `<svg><rect x="0" y="0" width="1024" height="1024" rx="${cornerRadius}" ry="${cornerRadius}" fill="white"/></svg>`
    );

    // 3. 执行裁切、缩放并应用圆角遮罩
    await sharp(inputPath)
        .extract({ left, top, width: cropW, height: cropH })
        .resize(1024, 1024, { fit: 'fill' }) // 拉伸到标准正方形
        .composite([{
            input: roundedCornersMask,
            blend: 'dest-in' // 只保留遮罩内的部分，其余变透明
        }])
        .png()
        .toFile(outputPath);

    console.log('处理完成！新图标已保存为 icon.png');
}

refineIcon().catch(console.error);
