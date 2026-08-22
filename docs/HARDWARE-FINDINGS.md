# Hardware findings

## Verified observations

| Layer | Observation |
| --- | --- |
| SoC | Qualcomm IPQ5332, 1 GiB DRAM |
| Wide-band radio | Qualcomm QCN6432 reported by the ath12k Wi-Fi 7 driver |
| Storage | 16 MiB SPI NOR plus 256 MiB Winbond W25N02KWZEIR serial NAND |
| Ethernet | 2.5 GbE full duplex in the validated deployment |
| Stock runtime | 2.4 GHz plus 5 GHz; wide-band slot reported AX-class operation |
| TIP NWA50BE DTS | `qcom,wide_band = <1>` on QCN6432 |
| Modified DTS | `qcom,wide_band = <2>` initializes QCN6432 in 6 GHz mode |
| Validated 6 GHz | Channel 5, EHT160, WPA3-SAE, LPI regulatory mode |

## What the evidence supports

The tested hardware can operate the QCN6432 as a 6 GHz Wi-Fi 7 radio under the
Qualcomm downstream stack. The stock product behavior does not expose that
mode. This is a real software policy distinction, not a claim that every RF
path, enclosure, board revision, or certification is interchangeable with a
different Zyxel SKU.

## What the evidence does not support

The evidence does not prove why the product is limited. Plausible reasons
include regulatory certification, antenna validation, SKU segmentation,
support cost, firmware maturity, or product positioning. Public documentation
should describe the mechanism and results without asserting hidden intent.

## Power semantics

The stock configuration can display a requested value such as 30 dBm while the
driver enforces band, country, antenna-gain, and firmware limits. In the tested
Italy 6 GHz LPI configuration, the kernel exposed 23 dBm EIRP. The live radio
reported 21 dBm conducted power with 2 dBi antenna gain. This project does not
patch regulatory tables or bypass DFS.
