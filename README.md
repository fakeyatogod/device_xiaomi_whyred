<p align="center" style="font-size:30px"><b>Device configurations for Redmi Note 5 Pro/AI (whyred)</b></p>

The Redmi Note 5 Pro/AI (codenamed as ``whyred``) are high-end mid-range smartphones from Xiaomi.

Xiaomi Redmi Note 5 was announced in Febraury 2018 and released in March 2018.

![Xiaomi Redmi Note 5 Pro](/whyred.png)

<p align="center" style="font-size:30px"><b>Device specifications</b></p>

> **Chipset** • Qualcomm® SDM660 (SoC) Snapdragon™ 636

> **CPU** • 4x Kryo™ 260 cores based on Cortex A73 + 4x Kryo™ 260 cores based on Cortex A53

> **GPU** •	Adreno 509

> **Memory** • 3GB / 4GB / 6GB RAM (LPDDR4X RAM)

> **Display** • 5.99 inches, 1080 x 2160 pixels, 18:9 ratio, IPS LCD capacitive touchscreen

> **Dimensions** • 158.6 x 75.4 x 8.05 (in mm)

> **Shipped Android version** •	Android™ 7.1.1 (codenamed as ``Nougat``)

> **Storage** •	64GB eMMC 5.1 flash storage

> **Battery** •	Non-removable Li-Po 4000 mAh

> **Rear camera 1** • Sony Exmor RS IMX486 12MP, 1.25-micron pixels, f/2.2 Dual LED flash

> **Rear camera 2** • Samsung S5K5E8 5 MP, 1.12-micron pixels, f/2.0

> **Front camera** • Sony Exmor RS IMX376 20 MP (f/2.2, 1/2.8", 1.0 μm), LED flash, 1080p

<p align="center" style="font-size:30px"><b>Device build instructions</b></p>

```
# Initialize the environment with the envsetup.sh script.
$ . build/envsetup.sh

# lunch whyred
$ lunch carbon_whyred

# run the make command. No of threads can be set by replacing $(nproc --all).
$ make carbon -j$(nproc --all)
```

___
