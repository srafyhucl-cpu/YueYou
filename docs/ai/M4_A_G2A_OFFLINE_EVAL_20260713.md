# M4-A/G2-A 离线技术基线报告

## 范围

本报告验证 M4-A 的最小离线能力：章节检索、引用定位、延迟和成本预算。
评测不调用网络、LLM、Embedding 服务或生产接口，不接触用户阅读数据。

## 评测输入

- 语料：`docs/ai/m4_g2_eval_corpus.json`，8 个预置西游记章节片段。
- 问题：`docs/ai/m4_g2_eval_cases.json`，8 个预置事实问题及期望章节/证据词。
- 实现：`scripts/m4_ai_eval.py`，确定性字符词元检索基线。

## 执行命令

```powershell
python -m unittest scripts/test_m4_ai_eval.py -v
python scripts/m4_ai_eval.py --corpus docs/ai/m4_g2_eval_corpus.json --cases docs/ai/m4_g2_eval_cases.json
```

## 结果

| 指标 | 结果 | G2-A 阈值 | 结论 |
| --- | ---: | ---: | --- |
| 预置事实题章节命中率 | 100%（8/8） | >= 85% | 通过离线基线 |
| 引用章节命中率 | 100%（8/8） | >= 90% | 通过离线基线 |
| P95 检索延迟 | 约 0.06ms | < 5s | 通过离线基线 |
| 离线估算成本 | 0 | <= 0.05 美元/请求 | 通过预算基线 |

Python 单元测试结果为 `3 tests OK`。评测器同时验证错误期望章节不能通过引用门禁。

## 边界

本报告只关闭 G2-A 的离线检索基线子项，不代表 LLM 生成质量、生产性能或用户价值。
接入真实模型后，必须用同一评测集重新测量准确率、引用率、P95 和实际 API 成本；G1 真机工程门通过前，
不得开放客户端 AI 入口或接入生产阅读数据。
