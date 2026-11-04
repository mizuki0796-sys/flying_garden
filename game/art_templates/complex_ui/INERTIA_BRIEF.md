# 空岛与飞船惯性
- 范围：运动、质量碰撞、双方损伤、低速对接、保存速度；外岛受损时复用地块耐久条显示。
- 保持：全部原位图、船体、港口、推进特效样式；不增加灯、烟、抖动。
- 无新素材或动画。惯性测试：tests/inertia_test.gd；外岛受损条沿用主岛(-28,22)、56×5参数。
- 实际绘制预览：去掉 headless 运行 inertia_test.gd；输出 artifacts/game/inertia/01-before-impact.png、02-both-damaged.png、03-island-coasting.png，固定时间2.35；未修改任何位图。
