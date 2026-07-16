# expense_based_subsidy

```drools
package rules;

import java.util.*;
import java.math.BigDecimal;
import com.maycur.sdk.rule.domain.*;
import com.maycur.sdk.rule.domain.result.*;
import com.maycur.sdk.rule.service.*;
import org.joda.time.DateTime;
import org.slf4j.Logger;

global AllowanceService allowanceService;
global Logger logger;

dialect "mvel"

// ==========================================
// 模式一：基于单笔费用 (Expense) 触发每日补贴计算
// 经典场景：只有报销单中报销了“住宿费 (typeCode == 2001_01)”且实际入住了，才按照住宿日期每天生成一笔出差补贴；退房当晚不产生补贴。
// ==========================================

rule "根据住宿费明细生成每日出差补贴"
    salience 20
    when
        Reimburse($expenses : expenses)
        // 匹配费用列表中小类编码为 2001_01 (住宿费) 的费用项
        $expense : Expense(
            typeCode == "2001_01",
            $baseCcy: baseCcy,
            $collectionCcy: collectionCcy,
            $endDate: endDate,
            $allowanceStandardInfos: allowanceStandardInfos
        ) from $expenses
        $allowanceStandardInfo : AllowanceStandardInfo() from $allowanceStandardInfos
        // 遍历该笔费用覆盖的具体天数区间
        $consumeTime : DateTime() from $expense.days()
        // 最后一晚（退房当天）不计算出差住宿补贴
        not (eval($endDate == $consumeTime))
    then
        BigDecimal stdRate = allowanceService.getAllowanceStandard($consumeTime, $allowanceStandardInfo);
        if (stdRate != null && stdRate.compareTo(BigDecimal.ZERO) > 0) {
            // 参数列表：消费日期, 补贴费用类型编码, 金额, 本币, 收款币种
            AllowanceResult result = new AllowanceResult($consumeTime, "88.004", stdRate, $baseCcy, $collectionCcy);
            // 将费用项上的消费城市与地址信息直接复制到补贴记录上
            allowanceService.copyLocationFromExpense($expense, result);
            insert(result);
        }
end


// ==========================================
// 模式二：行程总额累加更新模式 (insert 初始记录 + update 逐步累加)
// 经典场景：跨多天或跨档位标准时，先通过 salience 10 插入一条起止日期区间的初始总计明细(初额为0)，
// 再由 salience 2 的规则遍历每日金额并对工作内存中的 $result 执行 update() 动态求和。
// ==========================================

rule "初始化行程补贴汇总明细"
    salience 10
    when
        Reimburse($travelRoutes : travelRoutes, $baseCcy : baseCcy, $collectionCcy : collectionCcy)
        $travelRoute : TravelRoute(
            $startDate : new DateTime(startDate.getYear(), startDate.getMonthOfYear(), startDate.getDayOfMonth(), 0, 0, 0),
            $endDate : new DateTime(endDate.getYear(), endDate.getMonthOfYear(), endDate.getDayOfMonth(), 0, 0, 0)
        ) from $travelRoutes
    then
        // 构造起始金额为 ZERO 的总计区间补贴结果
        AllowanceResult result = new AllowanceResult($startDate, $endDate, "88.004", BigDecimal.ZERO, $baseCcy, $collectionCcy);
        allowanceService.copyLocationFromTravelRoute($travelRoute, result);
        result.setTravelRouteCode($travelRoute.getTravelRouteCode());
        insert(result);
end

rule "遍历每日标准并更新汇总金额"
    salience 2
    when
        Reimburse($travelRoutes : travelRoutes)
        $travelRoute : TravelRoute($allowanceStandardInfos : allowanceStandardInfos) from $travelRoutes
        $consumeTime : DateTime() from allowanceService.getTripDiffDays($travelRoute)
        $allowanceStandardInfo : AllowanceStandardInfo() from $allowanceStandardInfos
        // 匹配上一规则刚放入工作内存的未完成累加的条目
        $result : AllowanceResult(bizCode == "88.004")
        not (eval($travelRoute.getEndDate() == $consumeTime))
    then
        BigDecimal dailyAmt = allowanceService.getAllowanceStandard($consumeTime, $allowanceStandardInfo);
        if (dailyAmt != null && dailyAmt.compareTo(BigDecimal.ZERO) > 0) {
            // 对现有汇总条目的 amount 属性执行加法并调用 update() 刷新工作内存状态
            $result.setAmount($result.getAmount().add(dailyAmt));
            update($result);
        }
end
```
