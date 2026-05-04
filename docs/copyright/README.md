# 阅游软著材料说明

本目录用于存放阅游 V1.1.0 软件著作权申请材料。

## 文件说明

| 文件 | 说明 |
| --- | --- |
| `generate_source_pdf.py` | 源代码鉴别材料 PDF 生成脚本 |
| `generate_document_pdf.py` | 文档鉴别材料 PDF 生成脚本 |
| `源代码.pdf` | 60 页源代码鉴别材料，每页 50 行，覆盖 Flutter 客户端与 Go 服务端 |
| `阅游V1.1.0.md` | 设计与使用说明书源文档 |
| `阅游V1.1.0.pdf` | 设计与使用说明书文档鉴别材料，当前不足 60 页按规则提交整份 |
| `screenshots/` | 界面截图目录，按截图清单补充真实截图 |
| `申请清单.md` | 个人申请软著所需材料清单 |

## 生成源代码 PDF

```powershell
python docs/copyright/generate_source_pdf.py
```

生成文件：

```text
docs/copyright/源代码.pdf
```

## 生成文档 PDF

```powershell
python docs/copyright/generate_document_pdf.py
```

生成文件：

```text
docs/copyright/阅游V1.1.0.pdf
```

## 提交前注意

- 申请人姓名已填写为“胡传龙”
- 文档名称统一为“阅游V1.1.0”
- `screenshots/` 目录当前至少包含设置页隐私政策入口截图，其他真实 App 截图可继续补充后重新生成 PDF
- 软件名称、版本号、开发完成日期必须与申请表一致
- 纸质提交时建议使用 A4 纸单面打印

