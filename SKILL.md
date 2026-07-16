---
name: maycur_subsidy_drl
description: 每刻报销（Maycur）差旅补贴与费用计算 Drools (DRL) 规则脚本开发技能。当用户需要编写、排查、调试或优化每刻报销补贴脚本（如差旅补贴、餐饮补贴、自驾车补贴、同行人补贴、扣减及常驻地校验等）时触发本技能。
---

# 每刻报销补贴脚本 (Maycur Subsidy DRL) 开发指南

每刻报销通过规则引擎（Drools + Mvel 语法）动态执行 `.drl` 脚本，根据报销单/申请单（`Reimburse`）、行程信息（`TravelRoute`）、参与人信息（`TravelPartner`）及补贴标准配置，自动计算差旅补贴并生成对应的费用明细（`AllowanceResult`）。

> [!IMPORTANT]
> **🚀 零基础刚接触或新手开发必读**：
> 如果你是初次接触每刻脚本或希望快速上手，**请务必首先查阅** 👉 **[开发者极简零基础上手与排错指南 (Quick Start Guide)](file:///references/quick_start_guide.md)**！该文档精简了晦涩的概念，直接提供**可直接复制粘贴、改 3 个参数即可跑通**的全天和半天通用代码骨架，并收录了高频开发排错常见坑（如算完金额为 0、页面不出明细、Mvel 日期报错等）。
> 
> **🛠️ 需求调研、集成 Q&A 与底层排错必查手册**：
> **最新收录** 👉 **[每刻语雀官方 Q&A 与特殊集成逻辑手册 (yuque_qa_best_practices.md)](file:///references/yuque_qa_best_practices.md)**！详细解答了：① 需求对接必确认的 4 大准则；② 自定义档案作为标准行维度为什么 DRL 里不需要写判断；③ 多个目的地的默认匹配规则；④ 外币补贴 vs 申请单币种冲突处理；⑤ **阿里云 SLS 底层 Java 异常堆栈日志定位方法**。
> 
> **📚 45 个全量实操完整案例库**：
> 本技能库 `examples/` 目录下已全量内置 **45 个真实生产环境完整 `.drl` 脚本**（含所有 `1.1`~`1.13` 及 `2.1`~`2.19` 复杂场景）。所有案例均可在 👉 **[每刻官方场景与完整源码速查索引](file:///references/usg5m5_templates.md)** 中一键点击跳转查看！

---


## 一、 开发规范与注意事项 (Critical Rules)

1. **补贴标准列维度必须是城市**：在每刻后台配置"补贴标准"时，**必须使用城市维度**（即便是全公司统一标准，也要配置"全部城市"列维度），否则系统匹配标准金额时会返回 0 或异常。
2. **Salience 优先级分层**：
   - `salience 30`：初始化参数（`TravelHalfDayKeys` 或 `DateListTravelList` 等全局声明）
   - `salience 25`：预处理（如行程去重排序，生成 `DateListTravel` + `DateListTravelList`）
   - `salience 20`：报销人费用计算规则
   - `salience 10`：参与人费用计算规则（部分模板将报销人+参与人合并在一个 salience）
3. **生成的补贴必须插入内存**：通过 `insert(allowanceResult)` 保存到工作内存，金额为 0 时**不要执行 insert**（条件判断 `if(amount.compareTo(BigDecimal.ZERO) == 1)`）。
4. **申请单补贴挂靠行程**：必须调用 `allowanceResult.setTravelRouteCode($travelRouteCode)` 否则前端不显示。
5. **参与人有独立补贴标准字段**：`TravelRoute` 上的 `$partnerAllowanceStandardInfos`（`partnerAllowanceStandardInfos`）与报销人的 `$allowanceStandardInfos` **是两个不同字段**，必须正确区分使用。
6. **全天与半天两种模式**：半天模板内嵌 `isDayHalveOrOverlap` function；全天模板使用 `isDayOverlap` function（更简单，仅去重，不判断12点）。
7. **自定义档案作为标准维度无需写代码判断**：若后台将自定义档案（如【是否派车】）配置为补贴标准的行维度，**DRL 脚本中不需要写任何 `customFormValues` 判断分支**！系统底层会自动检查行程表单字段并精确匹配金额，不匹配自动为 null。
8. **多行程目的地计算规则**：当单条行程包含多个城市目的地时，系统**默认按最后一个目的地**匹配标准（亦支持在后台配置为最高/最低/首/尾标准）。
9. **外币补贴币种与汇率规范**：若补贴标准为外币（如 EUR），需删除申请单表单上的“申请币种”组件，由底层自动转换本币。DRL 脚本中可通过 `allowanceService.getDestinationAllowanceStandardCcy($startDate, $allowanceStandardInfo)` 获取标准配置的币种。

---

## 二、 两种核心 Helper Function（必读）

### 模式 A：全天去重 `isDayOverlap`（全天行程汇总类模板标配）
```java
function boolean isDayOverlap(Map map, String userCode, DateTime dateTime) {
    List days = null;
    if(map.get(userCode) == null) {
        days = new ArrayList();
    } else {
        days = (List)map.get(userCode);
    }
    String day = dateTime.toString("yyyy-MM-dd");
    if(!days.contains(day)) {
        days.add(day);
        map.put(userCode, days);
        return false;   // 未重叠，正常计算
    }
    return true;        // 重叠，跳过
}
```

### 模式 B：半天去重 `isDayHalveOrOverlap`（半天行程类模板标配）
返回值：`-1`=重叠跳过；`0`=半天（金额/2）；`1`=全天（正常金额）
```java
function int isDayHalveOrOverlap(Map map, String userCode, DateTime day, DateTime startDate, DateTime endDate) {
    int flag = 1;
    List days = (map.get(userCode) == null) ? new ArrayList() : (List)map.get(userCode);
    String amDay = day.toString("yyyy-MM-dd") + "am";
    String pmDay = day.toString("yyyy-MM-dd") + "pm";
    // 出发日：12点后出发 → 下午半天
    if(day.getYear()==startDate.getYear() && day.getMonthOfYear()==startDate.getMonthOfYear()
       && day.getDayOfMonth()==startDate.getDayOfMonth()) {
        if(startDate.getHourOfDay() >= 12) {
            if(days.contains(pmDay)) return -1;
            days.add(pmDay); map.put(userCode, days); return 0;
        }
    }
    // 返回日：12点前返回 → 上午半天；12:00整也算半天
    if(day.getYear()==endDate.getYear() && day.getMonthOfYear()==endDate.getMonthOfYear()
       && day.getDayOfMonth()==endDate.getDayOfMonth()) {
        if(endDate.getHourOfDay() < 12 || (endDate.getHourOfDay()==12 && endDate.getMinuteOfHour()==0)) {
            if(days.contains(amDay)) return -1;
            days.add(amDay); map.put(userCode, days); return 0;
        }
    }
    // 普通日期：上下午两个 slot 都没有才算全天
    if(days.contains(amDay) && days.contains(pmDay)) return -1;
    if(days.contains(amDay)) flag = 0; else days.add(amDay);
    if(days.contains(pmDay)) flag = 0; else days.add(pmDay);
    map.put(userCode, days);
    return flag;
}
```

> [!IMPORTANT]
> **两套标准区分 userCode**：当同一员工在两套标准（如 bizCodeOne 和 bizCodeTwo）中均需独立计算时，用 `userCode + "ONE"` 和 `userCode + "TWO"` 作为 map key，避免互相干扰（参见 1.5 两套标准模板）。

---

## 三、 declare 声明与全局参数

### 标准 `TravelHalfDayKeys`（全天模板）
```drools
declare TravelHalfDayKeys
    dateMap : Map    // 存储日期集合（key=userCode，value=List<String>）
    bizCode : String // 补贴标准业务编码
    feeCode : String // 生成的费用类型编码
end
rule "初始化参数"
    salience 30
    when Reimburse();
    then
        String bizCode = "footAllowance"; // TODO: 替换
        String feeCode = "BT";            // TODO: 替换
        insert(new TravelHalfDayKeys(new HashMap(), bizCode, feeCode));
end
```

### 高阶：`DateListTravel` + `DateListTravelList`（行程扣减/多行程连续扣减类）
```drools
declare DateListTravel
    travelRecord : TravelRoute
    validDateTimes : List
end
declare DateListTravelList
    travelRouteList : List
end
// salience 25 规则先做去重+排序，生成 DateListTravelList 后插入内存
// salience 20 规则从 DateListTravelList 读取，再做连续行程扣减逻辑
```
参见 [real_2.1_仅报销人_全天_单条行程汇总_行程扣减.drl](file:///examples/real_2.1_仅报销人_全天_单条行程汇总_行程扣减.drl) 完整实现。

---

## 四、 核心对象字段速查

### `TravelRoute` 关键字段（在 when 中绑定）
```drools
$travelRecord : TravelRoute(
    $startDate   : startDate,          // 行程出发时间 DateTime
    $endDate     : endDate,            // 行程返回时间 DateTime
    $destination : destination,        // 行程目的地编码 String（如 "330000-330100-330106"）
    $travelRouteCode : travelRouteCode, // 行程 Code，申请单挂靠行程必须设置
    $allowanceStandardInfos : allowanceStandardInfos,      // 报销人补贴标准信息 List
    $partnerAllowanceStandardInfos : partnerAllowanceStandardInfos, // 参与人补贴标准信息 List（不同于报销人！）
    $travelPartnerInfo : travelPartnerInfo  // 同行人信息对象
) from $travelRoutes;
```

### 参与人遍历（全天模板标准写法）
```java
// 循环参与人信息列表（注意：mvel 中调用 getter 可省略括号）
for(TravelPartner travelPartner : $travelPartnerInfo.getInternalTravelPartner) {
    BigDecimal partnerAllowanceAmount = allowanceService.getDestinationPartnerAllowanceStandard(
        dateTime,
        $partnerAllowanceStandardInfos,  // 使用参与人专属标准，不是报销人的
        travelPartner,
        $bizCode
    );
    if(!isDayOverlap($dateMap, travelPartner.getUserCode(), dateTime)) {
        amount = amount.add(partnerAllowanceAmount);
    }
}
```

### 常驻地校验（实际代码中使用地址编码字符串比较）
```java
// 判断市级：取编码 split("-") 的第 3 位（index=2）
String destination = $destination.split("-")[2].toString;
if(null != $reimEmployee.getResidences) {
    for(Residence re : $reimEmployee.getResidences) {
        String cityCode = re.getPlaceFullCode.split("-")[2].toString;
        if(cityCode.equals(destination)) {
            finalAmount = new BigDecimal("0");  // 常驻地不给补贴
        }
    }
}
// 判断省级：取 split("-")[0]（即 index=0）
```

### 费用折半扣减（有关联费用时对应日期金额减半）
```java
// 在初始化规则中收集触发扣减的费用日期
String typeBizCode = "2020_01"; // 触发扣减的费用类型
boolean consumeDate = true;     // true=单日消费；false=区间消费
List dateList = new ArrayList();
for(Expense expense : $expenses) {
    if(typeBizCode.equals(expense.getTypeBizCode())) {
        if(consumeDate) {
            dateList.add(expense.getConsumeDate().toString("yyyy-MM-dd"));
        } else {
            List dateTimes = allowanceService.getTripDiffDays(expense);
            for(Object obj : dateTimes) dateList.add(((DateTime)obj).toString("yyyy-MM-dd"));
        }
    }
}
// 在计算规则中判断
if($dateList.contains(dateTime.toString("yyyy-MM-dd"))) {
    amount = amount.add(allowanceAmount.multiply($ratio)); // 折半
} else {
    amount = amount.add(allowanceAmount);
}
```

### 行程选项扣减（行程 customFormValues 触发）
```java
// 在 when 中绑定行程自定义字段（需要判断具体字段值）
// 在 then 中读取行程的 customFormValues 并比对选项编码
// 参见 real_2.10_含报销人和参与人_全天_行程选项扣减.drl
```

### 行程多目的地、考勤工时联动与含早扣减 (官方高阶字段)
- **行程多目的地 (`destinationStandards`)**：对于一段行程存在多个城市的出差（官方 2026-06-25 新增），可从 `AllowanceStandardInfo.getDestinationStandards()` 取出 `List<DestinationAllowanceStandard>`，获取各个目的地城市的标准额度及停留序号 (`destIndex` / `total`)。
- **费用参与人补贴 (`expensePartnerStandardInfos`)**：若参与人补贴由单笔费用明细行触发（官方 2026-06-24 新增），通过 `Expense.getExpensePartnerStandardInfos()` 循环标准表。
- **考勤联动出差 (`attendance`)**：`TravelRoute.getAttendance()` 返回考勤对象，包含 `calcDaysMode` (`WORK_DAY` / `NATURAL_DAY`)、`durationUnit` (`DAY`/`HALF_DAY`/`HOUR`) 和实际时长 `duration` (`double`)，可直接结合 actual work hours 计算或者扣减补贴。
- **是否含早判定 (`containBreakfast`)**：`Expense.getContainBreakfast()` 返回整型状态码（`1`-含早 `2`-不含 `3`-未知/默认），广泛用于酒店费用报销同时关联扣减当天早餐费。

---

## 五、 AllowanceResult 构造与关键 Setter

```java
// 构造一：按行程区间（开始日期-结束日期，适合行程汇总）
AllowanceResult result = new AllowanceResult($startDate, $endDate, $feeCode, amount, currency, currency);
// 构造二：按单日（适合按天生成）
AllowanceResult result = new AllowanceResult($dateTime, $feeCode, allowanceAmount, currency, currency, $destination);

// 关键 Setter
result.setTravelRouteCode($travelRouteCode);    // 申请单挂靠行程（必须）
result.setConsumeLocation($destination);        // 设置消费城市（建议总是设置）
```

> [!TIP]
> **获取币种方式**：`allowanceService.getDestinationAllowanceStandardCcy($startDate, $allowanceStandardInfo)` 或从 `$allowanceStandardInfo.getStandardMap().get($bizCode + "DESTINATION")).getCurrency()`（国内外双套标准时使用后者）。

---

## 六、 国内/国外双套标准路由（实际代码模式）

```drools
// 国内规则：判断 destination 包含 "domestic" 关键字
rule "国内补贴规则"
    when
        $travelRecord: TravelRoute($destination:destination, ...) from $travelRoutes;
        eval($destination.contains("domestic"));  // 国内判断
        $allowanceStandardInfo: AllowanceStandardInfo($innerBizCode.equals(ruleBizCode)) from $allowanceStandardInfos;
        $map: Map(get($innerBizCode + "DESTINATION") != null) from $allowanceStandardInfo.getStandardMap();
    then ...

// 国外规则：判断 destination 包含 "abroad" 关键字
rule "国外补贴规则"
    when
        eval($destination.contains("abroad"));  // 国外判断
        ...
```
参见 [real_2.7_含报销人和参与人_全天_行程汇总_国内外两套标准.drl](file:///examples/real_2.7_含报销人和参与人_全天_行程汇总_国内外两套标准.drl)。

---

## 七、 完整真实模板索引（共 45 个全场景官方完整 .drl 脚本库）

> [!TIP]
> 本技能库已将每刻官方所有补贴场景（半天 `1.1`~`1.13` 系列，全天 `2.1`~`2.19` 系列，以及自定义表单/自驾车扩展模板）**共计 45 个完整 `.drl` 脚本**统一整理存放在 `examples/` 目录下！
> 请直接访问 👉 **[每刻官方全场景与完整源码速查链接总表 (usg5m5_templates.md)](file:///references/usg5m5_templates.md)** 即可一键跳转任意场景源码！以下仅列出 10 个最核心的高频精选模板：

### 半天（12:00 分界）精选核心系列
| 文件 | 场景 | 关键特性 |
| :--- | :--- | :--- |
| [real_1.1_仅参与人_半天_每人每天一条](file:///examples/real_1.1_仅参与人_半天_每人每天一条.drl) | 仅参与人 / 不汇总 | `isDayHalveOrOverlap` |
| [real_1.4_含报销人和参与人_半天_每人每天一条](file:///examples/real_1.4_含报销人和参与人_半天_每人每天一条.drl) | **最通用半天模板** / 报销人+参与人各自每天一条 | 双 rule，salience 20+10 |
| [real_1.5_含报销人和参与人_半天_行程汇总_两套标准](file:///examples/real_1.5_含报销人和参与人_半天_行程汇总_两套标准.drl) | 行程汇总 / 两套 bizCode（userCode+"ONE"/+"TWO"） | 两套标准分别用不同 salience |
| [real_1.6_含报销人和参与人_半天_按天汇总](file:///examples/real_1.6_含报销人和参与人_半天_按天汇总.drl) | 半天 / 每日所有人合并一条 | 报销人+参与人同一行合并计算 |
| [real_1.8_常驻地市级匹配为0](file:///examples/real_1.8_常驻地市级匹配为0.drl) | 常驻地匹配 → 金额归零 | `placeFullCode.split("-")[2]` |

### 全天精选核心系列
| 文件 | 场景 | 关键特性 |
| :--- | :--- | :--- |
| [real_2.1_仅报销人_全天_单条行程汇总_行程扣减](file:///examples/real_2.1_仅报销人_全天_单条行程汇总_行程扣减.drl) | 仅报销人 / 行程连续扣减（单天不扣，多天-1，相邻合并） | `DateListTravel`+`DateListTravelList`+`isContinuousDates` |
| [real_2.4_含报销人和参与人_全天_行程汇总](file:///examples/real_2.4_含报销人和参与人_全天_行程汇总.drl) | **最通用全天模板** / 报销人+参与人合并行程汇总 | `isDayOverlap` |
| [real_2.5_含报销人和参与人_全天_行程汇总_费用折半](file:///examples/real_2.5_含报销人和参与人_全天_行程汇总_费用折半.drl) | 有关联费用时对应日期折半 | `dateList`+`ratio` 参数 |
| [real_2.7_含报销人和参与人_全天_行程汇总_国内外两套标准](file:///examples/real_2.7_含报销人和参与人_全天_行程汇总_国内外两套标准.drl) | 国内/国外分别不同 bizCode | `destination.contains("domestic"/"abroad")` |
| [real_2.15_仅报销人_行程天数判断扣减](file:///examples/real_2.15_仅报销人_行程天数判断扣减.drl) | 多行程连续性判断扣减（复杂版） | 排序+`isContinuousDates`+`nextFirst` |

---

## 八、 开发流程 Checklist

1. **需求与Q&A调研（强烈建议优先对照 [语雀官方 Q&A 避坑手册](file:///references/yuque_qa_best_practices.md)）**：
   - 汇总方式？**按天**（每天一条）还是**按行程**（每段汇总一条）？
   - 人员范围？**仅报销人** / **仅参与人** / **都包含**？
   - 半天还是全天？是否需要 12:00 分界？
   - 是否有扣减条件？（常驻地 / 关联费用 / 行程选项 / 连续行程天数扣减）
   - 是否有多目的地（默认最后一条）或外币冲突处理？
   - 查阅：[语雀官方 Q&A 避坑手册](file:///references/yuque_qa_best_practices.md) | [极简上手手册](file:///references/quick_start_guide.md) | [API 手册](file:///references/api_reference.md)

2. **选择模板**（优先选 real_ 前缀的真实官方模板）：
   - 参见上表"七、完整真实模板索引"，选最贴近的真实代码文件
   - 参考场景分类索引：[usg5m5 场景速查](file:///references/usg5m5_templates.md)

3. **修改关键参数（TODO 标记处）**：
   - `bizCode`：补贴标准业务编码
   - `feeCode`：生成补贴的费用类型编码
   - `typeBizCode`：触发扣减的费用类型编码（扣减模板）
   - `ratio`：折半扣减比例（`BigDecimal.valueOf(0.5)` 即折半）
   - 国内/国外判断条件中的字符串（`"domestic"` / `"abroad"`）

4. **上传与测试及异常排错**：
   - 上传 `.drl` 至每刻管理后台 → **补贴规则** → 关联单据类型并开启补贴计算
   - 提交测试报销单，在控制台查看 `logger.info` 输出确认金额计算正确
   - **底层排错**：若前端报“生成失败”或空白且语法无误，**必须通过阿里云 SLS 查找运行时异常**（根据计算 URI `allowance/generate` 及 `entCode` 提取 `traceId`，在 SLS Logstore 中以 `<traceId> and __topic__ : rule-service` 搜索底层 Java 异常堆栈，参见 [SLS排错指南](file:///references/yuque_qa_best_practices.md#2-阿里云-sls-底层-java-异常堆栈排查步骤-极重中之重)）。
