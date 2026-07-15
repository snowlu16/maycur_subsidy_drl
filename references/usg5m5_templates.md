# 每刻官方补贴模板库场景速查索引

本文档根据 **usg5m5** 官方模板页面描述 + 本地真实代码文件综合整理。

---

## 一、半天（12:00 分界）系列

所有半天系列均内嵌 `isDayHalveOrOverlap` function，出发时间 ≥ 12:00 → 下午半天；返回时间 < 12:00 或 = 12:00:00 → 上午半天。

| 编号 | 场景描述 | 关键参数/特性 | 对应真实文件 |
| :--- | :--- | :--- | :--- |
| **1.1** | 含行程参与人；不汇总（每人每天一条）；申请单可挂行程 | 仅参与人版：无报销人 rule | `real_1.1_仅参与人_半天_每人每天一条.drl` |
| **1.1** | 含行程参与人 + 含报销人；不汇总（每人每天一条） | **最通用**双 rule 模板 | `real_1.4_含报销人和参与人_半天_每人每天一条.drl` |
| **1.2** | 含行程参与人 + 含报销人；按行程汇总；对应日期扣减比例 | `subtractFee` + 费用日期匹配扣减 | 参见本地 `1.2`/`1.3` 模板 |
| **1.3** | 含行程参与人 + 含报销人；按行程汇总 | 标准行程汇总（含过滤金额为0） | 参见本地 `1.3` 模板 |
| **1.4** | 含行程参与人 + 含报销人；按天汇总（所有人合并一天一条） | 半天按天汇总 | `real_1.6_含报销人和参与人_半天_按天汇总.drl` |
| **1.5** | 含行程参与人 + 含报销人；按行程汇总；两套补贴标准 | `userCode+"ONE"` / `userCode+"TWO"` 区分两套 map key | `real_1.5_含报销人和参与人_半天_行程汇总_两套标准.drl` |
| **1.6** | 含报销人常驻地匹配行程目的地 → 扣减为 0 | `placeFullCode.split("-")[2]`（市级） | `real_1.8_常驻地市级匹配为0.drl` |
| **1.7** | 有指定费用（如打车费）→ 对应日期补贴扣减（支持多次） | `subtractFee` 费用类型匹配，对应日期扣减一半 | 参见本地 `1.7` 模板 |

---

## 二、全天系列

全天系列使用更简单的 `isDayOverlap` function（只判断是否重叠，无半天逻辑）。

| 编号 | 场景描述 | 关键参数/特性 | 对应真实文件 |
| :--- | :--- | :--- | :--- |
| **2.1** | 含报销人；按行程汇总；多行程连续判断扣减（单天不扣，多天-1，相邻合并） | `DateListTravel` + `DateListTravelList` + `isContinuousDates` | `real_2.1_仅报销人_全天_单条行程汇总_行程扣减.drl` |
| **2.2** | 不含报销人；按行程汇总（仅参与人） | 简洁版，无报销人逻辑 | `real_2.2_不含报销人_全天_行程汇总.drl` |
| **2.3** | 不含报销人；按行程汇总；有关联费用则折半 | `dateList` 收集费用日期 + `ratio` | 参见本地 `2.3` 模板 |
| **2.4** | 含报销人 + 参与人；按行程汇总 | **最通用全天模板** | `real_2.4_含报销人和参与人_全天_行程汇总.drl` |
| **2.5** | 含报销人 + 参与人；按行程汇总；有关联费用则折半 | `dateList`+`ratio` 参数；`typeBizCode`+`consumeDate`（是否区间） | `real_2.5_含报销人和参与人_全天_行程汇总_费用折半.drl` |
| **2.6** | 含报销人 + 参与人；按天汇总；有关联费用则折半 | 每日 insert，`dateList` 折半 | 参见本地 `2.6` 模板 |
| **2.7** | 含报销人 + 参与人；按行程汇总；国内/国外两套标准 | `destination.contains("domestic"/"abroad")`；两 rule 分开；从 `standardMap.get(bizCode+"DESTINATION").getCurrency()` 取币种 | `real_2.7_含报销人和参与人_全天_行程汇总_国内外两套标准.drl` |
| **2.8** | 含报销人 + 参与人；按天汇总（所有人合并一天一条） | `isDayOverlap` 全天按日累计 | `real_2.8_含报销人和参与人_全天_按天汇总.drl` |
| **2.9** | 不含报销人；按天汇总 | 仅参与人按天合并 | 参见本地 `2.9` 模板 |
| **2.10** | 含报销人 + 参与人；行程内存在指定选项 → 按比例扣减 | `customFormValues` 匹配选项编码值；`deductionRate` | `real_2.10_含报销人和参与人_全天_行程选项扣减.drl` |
| **2.11** | 含报销人 + 参与人；行程汇总；多套补贴标准（2套或3套） | 多套 bizCode 分别循环各自 `allowanceStandardInfo` | 参见本地 `2.11` 模板 |
| **2.12** | 含报销人；全天单条汇总（复杂版） | 结合行程去重排序的复杂单条汇总 | 参见本地 `2.12` 模板 |
| **2.15** | 仅报销人；多行程连续判断扣减（高级版） | 排序+`isContinuousDates`+下一行程首日判断 | `real_2.15_仅报销人_行程天数判断扣减.drl` |

---

## 三、关键设计模式速查

### 行程扣减逻辑（2.1 / 2.15）
```
规则：
- 单段行程仅一天 → 不扣减（保留）
- 单段行程多天 → 末尾去掉最后一天（days.remove(size-1)）
- 相邻行程（两行程末日与下一行程首日相差 ≤ 86400000ms）→ 合并后再扣减末尾一天
- 不相邻行程 → 各自独立判断是否多天
```

### 两套标准区分（1.5）
```java
// 报销人用 userCode + "ONE" 和 userCode + "TWO" 作为不同 key
// 参与人用 travelPartner.getUserCode() + "ONE" 和 "TWO"
```

### 国内/国外路由（2.7）
```java
// 判断条件：
eval($destination.contains("domestic"));  // 国内路线
eval($destination.contains("abroad"));    // 国外路线
// 取币种方式：
String currency = ((AllowanceStandard)$map.get($bizCode + "DESTINATION")).getCurrency();
```

### 常驻地编码比对（1.8）
```java
// 市级匹配（index=2）
String destCity = $destination.split("-")[2].toString;
String empCity = re.getPlaceFullCode.split("-")[2].toString;
if(empCity.equals(destCity)) finalAmount = new BigDecimal("0");
// 省级匹配（index=0）
String destProv = $destination.split("-")[0].toString;
String empProv = re.getPlaceFullCode.split("-")[0].toString;
```
