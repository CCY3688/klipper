# ESP32 墨盒执行板配置

当前硬件识别结果：`USB-Enhanced-SERIAL CH9102 (COM20)`，芯片为
`ESP32-D0WD-V3 rev.3`，40 MHz 晶振，MAC `b4:8a:0a:8d:14:00`。

## 设计边界

现有 Klipper 源码没有 ESP32 微控制器后端，因此 ESP32 不能直接按
`[mcu]` 编译成 Klipper 固件。本项目采用专用执行板方案：STM32F407
继续控制 Delta 运动，ESP32 只负责 HP 63/302/123/803 墨盒的 I2S 波形；
Klipper 主机通过串口插件发送 42 字节喷嘴位图。没有 LCD、按键、传感器
或图片读取功能。

## Windows 环境

在项目根目录打开 PowerShell：

```powershell
. .\tools\esp32_env.ps1
esptool.py --port COM20 chip_id
```

已验证 `esptool` 可识别当前芯片。ESP-IDF 工程使用 4.4.7，原因是原始
墨盒 I2S 驱动来自 2022 年的 ESP-IDF 4.x 工程。工具链下载若被网络中断，
重新运行 IDF 4.4.7 的 `install.bat esp32` 即可；不要用 Arduino 固件覆盖
该工程。

编译和烧录命令如下。烧录前必须确认墨盒电源、3.3 V 电平转换和 HV 使能
电路已连接，且喷头没有接触纸面：

```powershell
. .\tools\esp32_env.ps1
Set-Location .\00_ref\printercart_simple
idf.py set-target esp32
idf.py build
idf.py -p COM20 flash
idf.py -p COM20 monitor
```

第一次只执行 `build`。`flash` 会覆盖 ESP32 的现有应用固件，但不会改动
STM32 或 Klipper 主机文件。

## Klipper 接入

将 `host/printercart_esp32.cfg` 的 `[printercart_serial]` include 到运行中
主机的 `printer.cfg`，并将 `port` 改成实际的 Linux 路径：

```bash
ls -l /dev/serial/by-id/
```

本仓库的 Klipper 备份中已加入 `klippy/extras/printercart_serial.py`。
连接后可使用这些安全的控制命令：

```gcode
CART_CONNECT
CART_STATUS
CART_OFF
CART_DISCONNECT
```

`CART_FIRE_HEX DATA=...` 会真正驱动墨盒喷嘴，只应由上层图像/笔画转换器
生成，禁止拿随机数据测试。串口协议为 `PING`、`OFF` 和
`FIRE <84位十六进制>`，其中 84 个十六进制字符对应 42 字节原始喷嘴位图。

## 原始墨盒引脚

固件沿用 `printercart_simple` 的原始接线：D1=GPIO27、D2=12、D3=13、
CSYNC=14、S2=32、S4=2、S1=4、S5=5、DCLK=18、S3=19、F3=15、F5=21。
GPIO2、GPIO4、GPIO5、GPIO12、GPIO15 属于 ESP32 启动/电源敏感引脚，
必须使用原设计的电平转换和上拉/下拉，不能直接把墨盒信号接到裸 GPIO。
