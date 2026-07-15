# 每刻补贴 SDK API 完整手册 (`AllowanceService` / `AllowanceResult`)

在 `.drl` 脚本中，系统默认注入了 `AllowanceService` 与 `Logger` 两个全局对象：
```drools
global com.maycur.sdk.rule.service.AllowanceService allowanceService;
global org.slf4j.Logger logger;
```

---

## 1. `AllowanceService` 官方完整方法速查

根据每刻官方最新 API 手册 (`https://openapi-ng.maycur.com/allowance/allowance.html`)，`AllowanceService` 提供以下关键方法供 DRL 规则直接调用：

### 1.1 行程与天数拆解方法
| 方法签名 | 描述与返回值 |
| :--- | :--- |
| `List<DateTime> getTripDiffDays(TravelRoute record)` | 根据行程的开始结束时间计算并拆解出涵盖的每一天 `DateTime` 列表（不考虑时分秒）。 |
| `List<DateTime> getTripDiffDays(Expense expense)` | 根据费用明细的开始结束时间计算涵盖的天数。 |
| `boolean isSameDay(DateTime startDate, DateTime endDate)` | 判断两个 Joda `DateTime` 对象是否属于自然日的同一天。 |
| `boolean isDayOfWeek(String dateTime)` | 静态方法 (`AllowanceService.isDayOfWeek(str)`)，判断 `yyyy-MM-dd` 格式日期是否是周六或周日。 |
| `boolean isSchedule(String optionCode, String dateTime, RuleScheduleValue ruleScheduleValue)` | 结合企业自定义排班/假期表 (`optionCode`) 判断指定日期是否为节假日/休息日。 |

### 1.2 补贴金额计算与获取方法
| 方法签名 | 描述与返回值 |
| :--- | :--- |
| `BigDecimal getAllowanceStandard(DateTime date, AllowanceStandardInfo standardInfo)` | 根据日期直接获取对应的补贴金额。 |
| `BigDecimal getDestinationAllowanceStandard(DateTime date, AllowanceStandardInfo standardInfo)` | 根据日期与行程目的地，获取目的地对应的具体补贴金额。 |
| `BigDecimal getPartnerAllowanceStandard(DateTime date, List<AllowanceStandardInfo> standardInfos, TravelPartner travelPartner, String ruleBizCode)` | 根据同行人/参与人 (`TravelPartner`) 和业务编码，获取其实际匹配的**出发地**补贴金额。 |
| `BigDecimal getDestinationPartnerAllowanceStandard(DateTime date, List<AllowanceStandardInfo> standardInfos, TravelPartner travelPartner, String ruleBizCode)` | 根据同行人 (`TravelPartner`) 和业务编码，获取其实际匹配的**目的地**补贴金额（建议同行人行程计算优选此方法）。 |
| `BigDecimal getAllowanceStandardAmountByCodeAndTime(List<AllowanceStandardInfo> standardInfos, DateTime dateTime, String ruleBizCode, boolean isDestination)` | 根据指定 `ruleBizCode` 和日期快速查询列表中的额度；`isDestination=true` 为取目的地额度。 |
| `BigDecimal getAmountByDateTime(List<TravelRoute> travelRoutes, DateTime dateTime, String ruleBiCode, boolean destination, boolean high)` | 针对重复或多段行程在同一天的场景，快速查询当天的所有匹配标准额度，并根据 `high` 参数取就高 (`true`) 或就低 (`false`) 标准。 |
| `List<AllowanceResult> getSumAllowancesGroupByAllowanceType(List<AllowanceResult> dailyAllowances)` | 将按天分散生成的 `AllowanceResult` 列表，根据补贴类型业务编码自动进行汇总。 |

### 1.3 币种处理与转换方法
| 方法签名 | 描述与返回值 |
| :--- | :--- |
| `String getAllowanceStandardCcy(DateTime date, AllowanceStandardInfo standardInfo)` | 根据日期获取对应补贴标准的币种字符串 (如 `"CNY"`、`"USD"` 等)。 |
| `String getDestinationAllowanceStandardCcy(DateTime date, AllowanceStandardInfo standardInfo)` | 根据日期与目的地获取目的地标准配置的对应币种字符串。 |

### 1.4 地址拷贝与常驻地校验方法
| 方法签名 | 描述与返回值 |
| :--- | :--- |
| `void copyLocationFromTravelRoute(TravelRoute travelRoute, AllowanceResult allowanceResult)` | 把行程上的出发城市和到达城市（以及每刻标准地址编码）完整拷贝设置到生成的补贴对象中。 |
| `void copyLocationFromExpense(Expense expense, AllowanceResult allowanceResult)` | 把单笔费用上的消费城市/出发地/到达地拷贝设置到补贴对象。 |
| `String getEmployeePlaceFullCode(Employee employee)` | 获取员工档案的第一常驻地编码字符串（如 `省-市-区`）。 |
| `boolean isResidence(Employee employee, TravelRoute travelRoute, boolean isDestination, boolean isContain)` | 判定行程的目的地或出发地是否为该员工常驻地。`isDestination=true` 校验目的地；`isContain=true` 开启非完全匹配校验（省/市包含匹配即返回 `true`）。 |

### 1.5 表单字段提取与费控查询方法
| 方法签名 | 描述与返回值 |
| :--- | :--- |
| `String getCustomFormValue(List<CustomFormValue> customFormValues, String bizCode)` | 快速自表单/组件列表中读取特定内码 `bizCode` 对应的填写的具体值或选项 Code。 |
| `ExpenseStandResult getKeyByFinalDimCodes(List<Expense> expenses)` | 按照 `人 + 日期 + 费控格子维度` 分组，自后台读取多维度费控上限标准金额返回。 |
| `ExpenseStandResult getKeyByRuleCode(List<Expense> expenses)` | 按照 `人 + 日期 + 费控规则` 分组，提取费控金额计算标准信息返回。 |

---

## 2. 核心自定义去重逻辑说明 (`isDayOverlap` / `isDayHalveOrOverlap`)

在每刻官方代码模板库中，除了 `AllowanceService` 的内置 API 之外，还有两段内嵌在 DRL 顶部作为 `function` 使用的核心自定义方法：

### 2.1 全天去重函数 `isDayOverlap` (全天行程类模板常用)
```java
function boolean isDayOverlap(Map map, String userCode, DateTime dateTime) {
    List days = (map.get(userCode) == null) ? new ArrayList() : (List)map.get(userCode);
    String day = dateTime.toString("yyyy-MM-dd");
    if(!days.contains(day)) {
        days.add(day);
        map.put(userCode, days);
        return false;   // 未计算过，返回 false 允许继续计算
    }
    return true;        // 已计算过，跳过
}
```

### 2.2 半天去重函数 `isDayHalveOrOverlap` (12:00 半天行程类模板必用)
```java
function int isDayHalveOrOverlap(Map map, String userCode, DateTime day, DateTime startDate, DateTime endDate) {
    int flag = 1;
    List days = (map.get(userCode) == null) ? new ArrayList() : (List)map.get(userCode);
    String amDay = day.toString("yyyy-MM-dd") + "am";
    String pmDay = day.toString("yyyy-MM-dd") + "pm";
    // 12点后出发 → 当天仅下午半天
    if(day.getYear()==startDate.getYear() && day.getMonthOfYear()==startDate.getMonthOfYear() && day.getDayOfMonth()==startDate.getDayOfMonth()) {
        if(startDate.getHourOfDay() >= 12) {
            if(days.contains(pmDay)) return -1;
            days.add(pmDay); map.put(userCode, days); return 0;
        }
    }
    // 12点前或12:00整到达 → 当天仅上午半天
    if(day.getYear()==endDate.getYear() && day.getMonthOfYear()==endDate.getMonthOfYear() && day.getDayOfMonth()==endDate.getDayOfMonth()) {
        if(endDate.getHourOfDay() < 12 || (endDate.getHourOfDay()==12 && endDate.getMinuteOfHour()==0)) {
            if(days.contains(amDay)) return -1;
            days.add(amDay); map.put(userCode, days); return 0;
        }
    }
    if(days.contains(amDay) && days.contains(pmDay)) return -1;
    if(days.contains(amDay)) flag = 0; else days.add(amDay);
    if(days.contains(pmDay)) flag = 0; else days.add(pmDay);
    map.put(userCode, days);
    return flag;
}
```

---

## 3. `AllowanceResult` 结果对象完整手册

`AllowanceResult` 是脚本向每刻引擎产出补贴费用的唯一载体，必须通过 `insert(result)` 放入 Drools 工作内存。

### 3.1 构造器列表 (`Constructors`)
官方一共提供 4 种基础重载构造器：

```java
// 1. 按单天消费日期构造
AllowanceResult(DateTime date, String bizCode, BigDecimal amount, String baseCcy, String collectionCcy)

// 2. 按单天消费日期 + 消费地点构造
AllowanceResult(DateTime date, String bizCode, BigDecimal amount, String baseCcy, String collectionCcy, String consumeLocation)

// 3. 按行程区间构造
AllowanceResult(DateTime startDate, DateTime endDate, String bizCode, BigDecimal amount, String baseCcy, String collectionCcy)

// 4. 按行程区间 + 目的地构造
AllowanceResult(DateTime startDate, DateTime endDate, String bizCode, BigDecimal amount, String baseCcy, String collectionCcy, String destination)
```
> [!NOTE]
> `bizCode` 是每刻后台配置的**补贴费用类型编码** (如 `"88.004"`)，必须写清楚；若补贴明细需要携带正确的消费地点/出发/达到城市，推荐直接在 `then` 代码块中调用 `allowanceService.copyLocationFromTravelRoute($travelRoute, result)`。

### 3.2 关键 Setters 与自定义表单写入

当补贴需要挂靠在具体的行程下在申请单或报销单界面展示时，**必须调用** `setTravelRouteCode`：
```java
// 核心：绑定具体行程 Code
result.setTravelRouteCode($travelRoute.getTravelRouteCode());
```

若针对刚创建出来的补贴费用行，还需要给其上的自定义表单（如辅助核算项目）赋默认值，可以使用官方提供的 `set*CustomObject` 方法：
```java
// 写入文本类型字段
result.setTextCustomObject("C1", "1");
// 写入数字类型字段
result.setNumberCustomObject("C3", new BigDecimal(3));
// 写入金额类型字段 (注意需包裹 MonetaryAmount)
result.setAmountCustomObject("C4", new MonetaryAmount(new BigDecimal(4), "CNY"));
// 写入下拉选项类型字段 (注意传值需为选项对应的业务编码 Code)
result.setOptionCustomObject("OPTION_BIZ_CODE", "SUB_OPTION_CODE");
```
