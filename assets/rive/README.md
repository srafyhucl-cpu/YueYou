# Rive 动画资源目录

## 开发期 Rive 文件

### xiaoyo.riv

- **来源**: [Lil Guy - Rive Community](https://rive.app/marketplace/18912-35694-lil-guy/)
- **用途**: 开发期资源核对与兼容测试，不是 Xiaoyo 2.0 商业母版
- **授权边界**: 来源为 Rive Community 的 Lil Guy，未取得阅游原创 IP 证明；不得用于商业资产定稿、版权登记或对外宣传
- **当前状态机**: 与 `XiaoyoStateMachine` 契约不一致，启用 `XIAOYO_V2_ENABLED` 时会自动回退静态角色
- **历史输入**: `lookX`、`lookY`、`onMerge`、`isGameOver` 仅保留给旧 2048 兼容组件

## Xiaoyo 2.0 契约

统一适配器位于 `lib/features/companion/presentation/`，状态机名称固定为
`XiaoyoStateMachine`，输入包括 `audioState`、`contextMode`、`lookX`、`lookY`、
`growthStage`、`energy`、`reduceMotion` 和七类低频触发器。当前仓库尚未生成原创
`xiaoyo_v2_base.riv`；在 IP-0 人工定稿和授权链完成前，不得把社区资源替换为商业母版。

## 历史下载步骤

1. 访问 [Rive Community 资源页](https://rive.app/marketplace/18912-35694-lil-guy/)
2. 点击 "Download" 下载 `.riv` 文件
3. 重命名为 `xiaoyo.riv`
4. 放到本目录下

## 注意事项

- 不得修改 `xiaoyo.riv` 充当原创母版；需要新建独立的 `xiaoyo_v2_base.riv`
- 原始文件输入名称不匹配时，产品代码应走静态回退，不应绕过统一契约强行绑定
- 新资产必须记录版本、来源、作者、授权范围、四视图和人工近似检查记录
