# template_1_3_trip_summary_two_standards

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
// 模板 1.3：含行程同行人 + 含报销人，按行程汇总（一段行程所有人汇总一条）
// 同时支持两套补贴标准（例如区分不同职级或不同出差类型的两套 bizCode）
//
// 参数说明：
//   bizCode1     - 第一套补贴标准业务编码
//   bizCode2     - 第二套补贴标准业务编码（例如高级别员工或国际路线使用）
//   feeCode      - 生成补贴费用的费用类型编码
// ==========================================

declare GlobalParams
    dateMap : Map
    bizCode1 : String
    bizCode2 : String
end

rule "初始化参数"
    salience 30
    when
        Reimburse()
    then
        insert(new GlobalParams(new HashMap(), "BIZ_CODE_1", "BIZ_CODE_2")); // TODO: 替换实际编码
end

// ---- 主计算规则：按行程汇总所有人金额 ----
rule "按行程汇总_含报销人和参与人"
    salience 20
    when
        GlobalParams($dateMap: dateMap, $bizCode1: bizCode1, $bizCode2: bizCode2)
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
    then
        BigDecimal totalAmount = BigDecimal.ZERO;
        String currency = $baseCcy;

        // 获取所有员工：报销人 + 行程同行人
        List allPersons = new ArrayList();
        allPersons.add($reimEmployee);
        if ($travelPartnerInfo != null && $travelPartnerInfo.getInternalTravelPartner() != null) {
            allPersons.addAll($travelPartnerInfo.getInternalTravelPartner());
        }

        // 遍历每天
        List dateTimes = allowanceService.getTripDiffDays($travelRoute);
        for (Object dt : dateTimes) {
            DateTime consumeTime = (DateTime) dt;

            for (Object personObj : allPersons) {
                String userCode;
                BigDecimal dailyRate = null;

                if (personObj instanceof Employee) {
                    Employee emp = (Employee) personObj;
                    userCode = emp.getUserCode();
                    // 先尝试 bizCode1，匹配不到则尝试 bizCode2
                    for (Object info : $allowanceStandardInfos) {
                        AllowanceStandardInfo stdInfo = (AllowanceStandardInfo) info;
                        if ($bizCode1.equals(stdInfo.getRuleBizCode()) || $bizCode2.equals(stdInfo.getRuleBizCode())) {
                            BigDecimal rate = allowanceService.getDestinationAllowanceStandard(consumeTime, stdInfo);
                            if (rate != null && rate.compareTo(BigDecimal.ZERO) > 0) {
                                dailyRate = rate;
                                currency = allowanceService.getDestinationAllowanceStandardCcy(consumeTime, stdInfo);
                                break;
                            }
                        }
                    }
                } else if (personObj instanceof TravelPartner) {
                    TravelPartner partner = (TravelPartner) personObj;
                    userCode = partner.getUserCode();
                    if (userCode == null) continue;
                    dailyRate = allowanceService.getDestinationPartnerAllowanceStandard(consumeTime, $allowanceStandardInfos, partner, $bizCode1);
                    if (dailyRate == null || dailyRate.compareTo(BigDecimal.ZERO) == 0) {
                        dailyRate = allowanceService.getDestinationPartnerAllowanceStandard(consumeTime, $allowanceStandardInfos, partner, $bizCode2);
                    }
                } else {
                    continue;
                }

                // 重叠检查（全天模式下不做半天）
                int status = allowanceService.isDayHalveOrOverlap($dateMap, userCode, consumeTime, $startDate, $endDate);
                if (status == -1 || dailyRate == null || dailyRate.compareTo(BigDecimal.ZERO) <= 0) {
                    continue;
                }

                totalAmount = totalAmount.add(dailyRate);
            }
        }

        if (totalAmount.compareTo(BigDecimal.ZERO) > 0) {
            AllowanceResult result = new AllowanceResult($startDate, $endDate, "YOUR_FEE_CODE", totalAmount, $baseCcy, currency, $destination);
            result.setTravelRouteCode($travelRoute.getTravelRouteCode());
            insert(result);
        }
end
```
