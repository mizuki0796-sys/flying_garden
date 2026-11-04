# 飞船与港口接入游戏

- 用户要求：把已制作的飞船和港口 UI 接入游戏，提供几张实际游戏截图。
- 范围：替换两处占位绘制；复用双桨组件；港口根据相邻空格朝外，泊位移至该侧 64px；整岛规划同步显示。
- 母版：`game/assets/pixel_v2/facilities/harbor_directions_v3.png`，SHA-256 `7DB5CECC18F8AE0B6DDD52B427A4ECCB2A8CAE9101B3BDCE6D7D4BB37CB84198`；`game/assets/pixel_v2/vehicles/collector_v2.png`，SHA-256 `2A7CF3D53D94D43D0C52924F9A4E3E61FF0BFCADD012203876C0102BCCAE528B`。均为原素材逐字节复制，未生成或重画位图。
- 港口：四向源矩形见 `harbor_visual.gd::REGIONS`，按原比例适配北南 80×56、东西 52×64；仅在运行时去除 alpha<0.9 的概念图光晕。其余源像素不变，不声称四向可无缝拼接。
- 飞船：完整画布 56×56；原双桨轴心、遮罩、反向旋转、0.8 秒周期不变。336×336 透明 SubViewport 复用组件，合成回原世界绘制顺序，保留天气与界面覆盖关系。
- 保持：其余建筑、船身、货物、固定支架、轴帽和已有特效；建造成本、唯一限制、电池、采矿与卸货规则、存档格式不变。没有新增灯、烟、抖动、船体旋转或状态。
- 不变区验证：复制素材 SHA-256 一致；双桨已有像素验证继续使用同一组件；本次检查实际建造、四边朝向、外侧泊位、出航和召回。
- 截图：1152×648，10:00，动画时间 2.35，风力 0.14；全景 1 倍、近景 3 倍。`tests/harbor_ship_preview.gd` 调用实际场景和绘制函数，输出 `artifacts/game/harbor-ship-integrated/` 三张图。未要求新视频。
- 复现：Godot `--path game --script res://tests/harbor_ship_preview.gd --rendering-method gl_compatibility --audio-driver Dummy`，需要图形渲染环境。
- 验证结果：玩法 142 项、整岛规划 60 项全部通过；三张真实 viewport 截图完成，外侧停泊/出航/召回断言通过。双桨 GPU 验证 80 帧通过范围、固定轴帽、实心桨叶和循环检查；每帧保护 367988 个非运动像素及 5505 个轴帽像素。日志见截图目录 `godot.log` 与 `rotor-check.log`。环境有系统证书库读取警告，未影响渲染与测试。
- 未检查：导出安装包及长时间运行性能；没有扩展模块拼接玩法。
