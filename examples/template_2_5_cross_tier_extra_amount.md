# template_2_5_cross_tier_extra_amount

```drools
package rules;

import java.util.*;
import java.math.BigDecimal;
import java.math.RoundingMode;
import com.maycur.sdk.rule.domain.*;
import com.maycur.sdk.rule.domain.result.*;
import com.maycur.sdk.rule.service.*;
import org.joda.time.DateTime;
import org.slf4j.Logger;

global AllowanceService allowanceService;
global Logger logger;

dialect "mvel"

// ==========================================
// 模板 2.5：含行程同行人 + 含报销人，按天汇总（每天所有人合并一条）
// 核心特性：跨区间增加金额
//           根据出差累计天数所处区间，在当日标准基础上额外增加补贴金额
//           （如第 1-3 天：+0；第 4-7 天：+50；第 8 天以上：+100）
//
// 参数说明：
//   bizCode         - 补贴标准业务编码
//   feeCode         - 生成补贴费用的费用类型编码
//   extraAmountMap  - 区间额外增加额（key=从第N天开始的日序，value=每人每天额外增加金额）
//
// 逻辑：跨区间后，对应日期所有人都会加上这个额外金额
// ==========================================

declare GlobalParams
    dateMap : Map
    bizCode : String
    dayCounter : Map     // 存储每人的累计出差天数
end

rule "初始化参数"
    salience 30
    when
        Reimburse()
    then
        insert(new GlobalParams(new HashMap(), "YOUR_BIZ_CODE", new HashMap()));
end

rule "按天汇总_跨区间增加金额"
    salience 20
    when
        GlobalParams($dateMap: dateMap, $bizCode: bizCode, $dayCounter: dayCounter)
        Reimburse(
            $travelRoutes: travelRoutes,
            $reimEmployee: reimEmployee,
            $baseCcy: baseCcy
        )
        eval($reimEmployee != null)
        $travelRoute : TravelRoute(
            $startDate: startDate,
            $endDate: endDate,
            $destination: destination,
            $allowanceStandardInfos: allowanceStandardInfos,
            $travelPartnerInfo: travelPartnerInfo
        ) from $travelRoutes
        $allowanceStandardInfo: AllowanceStandardInfo(
            $bizCode.equals(ruleBizCode)
        ) from $allowanceStandardInfos
        $consumeTime: DateTime() from allowanceService.getTripDiffDays($travelRoute)
    then
        // ===== 可调参数：跨区间额外增加金额 =====
        // 配置：出差累计天数 >= key 时，每人每天额外加 value 元
        // 例：第4天开始额外加50，第8天开始额外加100
        Map extraAmountByDayThreshold = new TreeMap();  // TreeMap 保证按 key 排序
        extraAmountByDayThreshold.put(4, new BigDecimal("50.00"));    // 第4天+50
        extraAmountByDayThreshold.put(8, new BigDecimal("100.00"));   // 第8天+100
        // ==========================================

        // 收集该天所有参与者
        List allPersons = new ArrayList();
        allPersons.add($reimEmployee);
        if ($travelPartnerInfo != null && $travelPartnerInfo.getInternalTravelPartner() != null) {
            allPersons.addAll($travelPartnerInfo.getInternalTravelPartner());
        }

        BigDecimal totalForDay = BigDecimal.ZERO;
        String currency = $baseCcy;

        for (Object personObj : allPersons) {
            String userCode;
            if (personObj instanceof Employee) {
                userCode = ((Employee) personObj).getUserCode();
            } else if (personObj instanceof TravelPartner) {
                TravelPartner tp = (TravelPartner) personObj;
                userCode = tp.getUserCode();
                if (userCode == null) continue;
            } else {
                continue;
            }

            int status = allowanceService.isDayHalveOrOverlap($dateMap, userCode, $consumeTime, $startDate, $endDate);
            if (status == -1) continue;

            BigDecimal dailyRate;
            if (personObj instanceof Employee) {
                dailyRate = allowanceService.getDestinationAllowanceStandard($consumeTime, $allowanceStandardInfo);
            } else {
                dailyRate = allowanceService.getDestinationPartnerAllowanceStandard($consumeTime, $allowanceStandardInfos, (TravelPartner)personObj, $bizCode);
            }
            if (dailyRate == null) dailyRate = BigDecimal.ZERO;

            if (currency == null || currency.equals($baseCcy)) {
                currency = allowanceService.getDestinationAllowanceStandardCcy($consumeTime, $allowanceStandardInfo);
            }

            // 计算该员工累计出差天数（用于跨区间判断）
            int currentCount = (int) $dayCounter.getOrDefault(userCode, 0);
            currentCount += 1;
            $dayCounter.put(userCode, currentCount);

            // 根据累计天数确定额外增加金额（取最高满足条件的档位）
            BigDecimal extraAmount = BigDecimal.ZERO;
            for (Object keyObj : extraAmountByDayThreshold.keySet()) {
                int threshold = (int) keyObj;
                if (currentCount >= threshold) {
                    extraAmount = (BigDecimal) extraAmountByDayThreshold.get(keyObj);
                }
            }

            totalForDay = totalForDay.add(dailyRate).add(extraAmount);
        }

        if (totalForDay.compareTo(BigDecimal.ZERO) > 0) {
            // 按天汇总：所有人合并为当天一条记录，消费时间为该日
            AllowanceResult result = new AllowanceResult($consumeTime, "YOUR_FEE_CODE", totalForDay, $baseCcy, currency);
            allowanceService.copyLocationFromTravelRoute($travelRoute, result);
            result.setTravelRouteCode($travelRoute.getTravelRouteCode());
            insert(result);
        }
end
```
