# RigKit 设计说明（中文）

> 需求来源：《烬塔》完整设定与开发指导文档 v1.8 附录 P「Spine 骨骼动画运行时增强清单」。
> 本文记录“把附录 P 的 P0 落到一个独立开源工具”的取舍、实现与验收口径；核对了 P.3 / P.6 / P.7 / P.8 的每一条，
> 并标出**有意偏离**的地方与原因。

## 1. 边界：只做运行时那半边

附录 P.1 的结论是“能对标的是运行时（求解、约束、IK、锁脚、混合），编辑器那半边继续买编辑器”。
RigKit 严格按这条边界落地：

| 做 | 不做 |
|---|---|
| 动画写完之后重摆骨骼（Rotate only） | 改动画数据、K 帧、曲线编辑、绑定、镜像、导出 |
| 解析式双骨 IK、锁脚状态机、地面采样、调试可视 | 逆向任何商业运行时、复制其内部实现或数据表 |
| 任意骨骼源的适配层 | 自带/内置任何第三方运行时 |

**零拉伸是结构性保证**：RigKit 只写旋转，从不写位移，所以骨骼长度不可能被改变；超长时钳制的是
*目标点*，不是骨头。

## 2. 单脚状态机（P.3-1 的落地）

```
                 contact ≥ land && 双探针命中
   FK / LIFT ───────────────────────────────► PRE_CONTACT
      ▲                                          │ 权重 0→1
      │ 权重到 0                                 ▼
   RELEASE ◄──── contact < lift ────────────  LOCKED
                  或 地面丢失（degraded）
```

- **进入锁定是双条件与**（P.3-1）：`contact ≥ land_threshold` **且** 双探针都命中有效地面。
  只有曲线不算落地，只有地面不算落地，避免“脚本化的假踩地”。
- **退出用滞回**：`lift_threshold < contact < land_threshold` 区间内不动作，防止曲线噪声抖动。
- **权重曲线单调**（P.8.2）：`weight` 按 `dt / blend_time` 线性推进，`ease_in_out` 只作用于**姿势插值**，
  所以权重本身永远单调、无 0→1 硬跳；`blend_time` 下限 0.03 s（P.3-1 硬要求）。
- **掉地降级**（P.8.6）：`LOCKED` 时探针失效 → 立即 `RELEASE` 并置 `degraded`，权重回落到动画位置，不崩骨骼。

## 3. 两种锁法：一处**有意的偏离**

P.3-3 原文：

- 原地循环动画（root 由输入/AI 驱动）→ 锁**相对 root 的偏移**；
- 根运动动画 → 锁世界坐标 + 校验 root 增量。

实现里两种都做了（`LockMode.ROOT_RELATIVE` / `WORLD`），但**默认取 WORLD**，原因写清楚：

| 模式 | 目标 | 结果 | 适用 |
|---|---|---|---|
| `WORLD` | 落地瞬间的世界点，全程不动 | 脚在世界里真的不动（滑步 = 0），腿随身体压缩/伸展 | 站姿、走跑、任何“脚要钉住地面”的场景 |
| `ROOT_RELATIVE` | `root * 落地时的 root 局部偏移` | 脚随身体一起走，腿姿态恒定（相对身体不滑，世界里会滑） | 只有“锚点相对身体漂移”的原地循环，或 root 会被外部强行瞬移时 |

`ROOT_RELATIVE` 在世界上仍然会滑，这与 P.8.1「锁定脚掌每帧水平位移 ≤ 1 px」直接矛盾；
所以**验收用 WORLD**，`ROOT_RELATIVE` 作为兼容选项保留（P.3-3 的字面实现），并在
`docs/acceptance.md` 里单独标注它的行为，避免被误当成“零滑步”方案。

## 4. 双骨 IK（P.3-2）

`TwoBoneIK.solve()` 是纯数学，不碰骨骼：

1. `d = |target - hip|`，钳制到 `[|l1-l2|+ε, l1+l2-ε]`，超出部分计入 `clamp_ratio`；
2. 余弦定理解出大腿夹角 `alpha`；
3. **膝盖朝向**由世界极向量 `knee_axis` 决定：`sign(cross(target-hip, knee_axis))`，
   所以目标横扫过髋轴时膝盖不会翻面（P.8 未写但实测最容易翻车的一条，已加回归测试）；
4. 输出世界角度，按 `weight` 与 FK 角度做 `lerp_angle` 混合。

写回时**不需要读引擎的脏变换**：`local = 目标世界角 - 父骨新世界角 - 轴偏移`，父骨的新世界角由链自己算出来
（`upper` 目标角 → `lower` 目标角 → `foot`），因此一帧内父子顺序无依赖、无延迟。

轴偏移（`dir_offset`）把“运行时自己的旋转值”和“骨骼轴向”分开：+X 骨骼为 0，+Y 骨骼为 -90°。
叶骨（脚）没有子骨可探测，走 `tip_axis_deg` 显式配置。

## 5. 地面采样（P.3-4）

- 每脚两个探针（脚跟 / 脚尖），**都命中才有效**；
- `ShapeCast2D` + 小圆形状扫描（半径默认 0.03），不是单点射线：凹凸地面只影响“最先接触的那一边”，
  不会逐帧跳；
- 形状扫描的起点必须离地一个半径以上（`start_lift = radius + 0.02`），否则 ShapeCast 判定“起始重叠”直接返回未命中；
- 高度与坡度做 3~5 帧滑动平均；坡度取 `heel → toe` 连线的方向角；
- 脚旋转跟随坡度但**限制在 ±tilt_limit**（默认 20°，与 P.6 一致）；
- 探针层与 LoS / 投射物共用（默认 layer 1），装饰物不参与落地。

## 6. 安全护栏（“不许把腿拉爆”）

| 护栏 | 触发 | 动作 |
|---|---|---|
| 腿长钳制衰减 | `clamp_ratio > clamp_tolerance`（默认 0.12） | `safety` 按 `safety_fade_speed` 衰减，姿势权重回落，允许受控微量滑 |
| root 步长护栏 | 单帧 root 位移 > `root_step_tolerance` | 同上衰减（root motion 动画跑太快时的兜底） |
| 双腿互斥 | 两脚 `pose_weight > 0.85` 超过 `double_support_max`（默认 0.10 s） | 释放接触更弱的那只，并 `block_landing()`，它必须先离地才能再落 |
| 探针丢失 | 任一探针未命中 | `RELEASE` + `degraded`，回动画 |
| 总开关 | `set_enabled(false)` | 立刻清锁、不再写骨骼（原生 A/B 取证用） |

## 7. 与《烬塔》现有口径的对齐（P.6）

| 口径 | RigKit 对应 |
|---|---|
| 步频 3.5 步/秒、跑循环每步 1.6 m（零滑步 5.6 m/s） | `RigKitParams.apply_preset("run")`；`sprint` 供更高节奏 |
| contact 曲线抬脚 0 / 踩实 1、过渡 ≥ 3 帧 | `ContactSource.CURVE`（`set_contact_provider` / `set_contact`），`blend_time ≥ 0.03 s` |
| 2:1 dimetric、探针沿世界 Y 形状扫描、脚旋转 ±20° | `PhysicsProbeSampler` 沿 `Vector2(0, depth)` 扫描；`tilt_limit_deg = 20` |
| 探针与 LoS / 投射物共用 layer 1 | `params.ground_layer = 1`（`@export_flags_2d_physics`） |
| 序列帧贴地与骨骼锁脚不能同时挂 | 总开关 `enabled`，或干脆不挂 rig |
| 不允许“靠 IK 硬拉遮丑” | 钳制衰减 + 步幅口径；超出 ±15% 应该改步幅/步态，而不是调大 `clamp_tolerance` |

## 8. 文件地图

| 文件 | 职责 |
|---|---|
| `core/two_bone_ik.gd` | 解析式双骨 IK、极向量膝盖、IK/FK 混合、脚掌对地角度 |
| `core/rigkit_math.gd` | SmoothDamp、滑动平均、角度工具 |
| `core/ground_probe.gd` | 双探针采样、滤波、坡度与倾斜限幅 |
| `core/physics_probe_sampler.gd` | `ShapeCast2D` 采样器（可选，测试可注入假采样器） |
| `core/foot_lock.gd` | 单脚四态机、锚点、两种锁法、安全衰减 |
| `core/bone_chain.gd` | 骨骼链绑定、长度测量、FK 读取、姿势写回 |
| `core/foot_lock_rig.gd` | 编排：两脚、探针、接触源、双腿互斥、状态快照 |
| `adapters/node2d_bone_source.gd` | Node2D / Bone2D / Skeleton2D |
| `adapters/dict_bone_source.gd` | 字典骨骼（无头测试、程序化角色） |
| `adapters/spine_bone_source.gd` | 可选：spine 风格运行时的公开骨骼接口（鸭子类型 + 自定义 accessors） |
| `debug/rig_debug_draw.gd` | 探针、命中、锚点、IK 目标、腿长、状态文字 |

## 9. 后续（P.4 / P.5）

- P1：Aim 指向约束（角速度限制 + SmoothDamp）、Transform 跟随约束、RootMotion 步长审计
  （超阈值调 `anim_rate_mult`，不硬拉 IK）。
- P2：Chain IK（尾巴/触手，带末端朝向）、轻量 Verlet（头发/披风）。
- 每个能力都要求同样的“可判定验收”，不接受“手感还行”。

## 10. 非侵权声明

- 算法为教科书写法（余弦定理双骨 IK、滞回状态机、滑动平均），未参考任何商业运行时实现；
- 不包含、不内嵌、不分发任何第三方运行时或编辑器代码；
- `spine_bone_source.gd` 只调用使用者已获授权的运行时**公开**骨骼访问器，且暴露 `api` 字典让使用者
  用 5 个回调自行接管，不做任何逆向；
- 仓库名与文案不含任何第三方产品名，仅在文档里做兼容性说明，并注明商标归属与非隶属关系。
