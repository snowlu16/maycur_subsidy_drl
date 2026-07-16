# standard_daily_subsidy

```drools
package rules;

import java.util.*;
import java.math.BigDecimal;
import com.maycur.sdk.rule.domain.*;
import com.maycur.sdk.rule.domain.result.*;
import com.maycur.sdk.rule.service.*;
import org.joda.time.Days;
import org.joda.time.DateTime;
import org.joda.time.format.DateTimeFormat;
import org.slf4j.Logger;

global AllowanceService allowanceService;
global Logger logger;

dialect "mvel"

// ==========================================
// 1. 全局参数声明：用于跨规则存储已计算日期集合及标准编码
// ==========================================
declare TravelHalfDayKeys
    dateMap : Map       // 存储每个员工已计算/去重的出差日期集合
    bizCode : String    // 补贴标准后台对应的业务编码
end

// ==========================================
// 2. 初始化参数 (优先级最高 salience 30)
// ==========================================
rule "初始化参数"
    salience 30
    when
        Reimburse(); // 确保存在单据
    then
        // 注意：根据客户实际在每刻后台配置的补贴标准编码修改此处
        String bizCode = "dailyAllowanceStandard"; 
        insert(new TravelHalfDayKeys(new HashMap(), bizCode));
end

// ==========================================
// 3. 报销人费用规则计算 (salience 20)
// 逻辑：按天拆解行程，每天一条补贴；区分12:00半天；过滤重叠日期；挂载消费地/行程Code
// ==========================================
rule "报销人费用规则计算"
    salience 20
    when
        TravelHalfDayKeys(
            $dateMap: dateMap,
            $bizCode: bizCode
        );
        Reimburse(
            $travelRoutes: travelRoutes,
            $reimEmployee: reimEmployee,
            $collectionCcy: collectionCcy,
            $baseCcy: baseCcy
        );
        eval($reimEmployee != null);
        $travelRecord : TravelRoute(
            $startDate: startDate,
            $endDate: endDate,
            $destination: destination,
            $allowanceStandardInfos: allowanceStandardInfos
        ) from $travelRoutes;
        $allowanceStandardInfo : AllowanceStandardInfo(
            $bizCode.equals(ruleBizCode)
        ) from $allowanceStandardInfos;
        // 拆解该段行程包含的具体日期
        $dateTime : DateTime() from allowanceService.getTripDiffDays($travelRecord);
    then
        // 1. 检查该报销人当天是否已计算过或重叠以及半天判断
        int status = allowanceService.isDayHalveOrOverlap($dateMap, $reimEmployee.getUserCode(), $dateTime, $startDate, $endDate);
        if (status == -1) {
            // -1 表示该日期存在重叠已计算过，直接跳过
            return;
        }

        // 2. 获取当天的标准补贴金额和币种
        BigDecimal dailyRate = allowanceService.getDestinationAllowanceStandard($dateTime, $allowanceStandardInfo);
        if (dailyRate == null || dailyRate.compareTo(BigDecimal.ZERO) <= 0) {
            return;
        }

        // 3. 如果是半天 (status == 0)，金额减半
        BigDecimal actualAmount = dailyRate;
        if (status == 0) {
            actualAmount = dailyRate.multiply(new BigDecimal("0.5"));
        }

        // 4. 获取币种
        String currency = allowanceService.getDestinationAllowanceStandardCcy($dateTime, $allowanceStandardInfo);
        if (currency == null) {
            currency = $baseCcy;
        }

        // 5. 构造并生成补贴明细记录 (注意修改 "88.004" 为系统中实际的费用类型编码)
        AllowanceResult allowanceResult = new AllowanceResult($dateTime, "88.004", actualAmount, $baseCcy, currency);
        
        // 绑定消费城市与行程关联 (保证申请单明细挂行程下正常显示)
        allowanceResult.setConsumeLocation($destination);
        allowanceResult.setDestination($destination);
        allowanceResult.setTravelRouteCode($travelRecord.getTravelRouteCode());

        insert(allowanceResult);
end

// ==========================================
// 4. 同行人(参与人)费用规则计算 (salience 15)
// 逻辑：同上，从行程中获取同行人并独立为每一位同行人每天生成一条补贴
// ==========================================
rule "同行人费用规则计算"
    salience 15
    when
        TravelHalfDayKeys(
            $dateMap: dateMap,
            $bizCode: bizCode
        );
        Reimburse(
            $travelRoutes: travelRoutes,
            $collectionCcy: collectionCcy,
            $baseCcy: baseCcy
        );
        $travelRecord : TravelRoute(
            $startDate: startDate,
            $endDate: endDate,
            $destination: destination,
            $allowanceStandardInfos: allowanceStandardInfos,
            $travelPartnerInfo: travelPartnerInfo
        ) from $travelRoutes;
        $allowanceStandardInfo : AllowanceStandardInfo(
            $bizCode.equals(ruleBizCode)
        ) from $allowanceStandardInfos;
        // 遍历同行人列表
        $travelPartner : TravelPartner() from $travelPartnerInfo.getInternalTravelPartner();
        $dateTime : DateTime() from allowanceService.getTripDiffDays($travelRecord);
    then
        if ($travelPartner == null || $travelPartner.getUserCode() == null) {
            return;
        }
        int status = allowanceService.isDayHalveOrOverlap($dateMap, $travelPartner.getUserCode(), $dateTime, $startDate, $endDate);
        if (status == -1) {
            return;
        }

        BigDecimal dailyRate = allowanceService.getDestinationPartnerAllowanceStandard($dateTime, $travelRecord.getAllowanceStandardInfos(), $travelPartner, $bizCode);
        if (dailyRate == null || dailyRate.compareTo(BigDecimal.ZERO) <= 0) {
            return;
        }

        BigDecimal actualAmount = dailyRate;
        if (status == 0) {
            actualAmount = dailyRate.multiply(new BigDecimal("0.5"));
        }

        String currency = allowanceService.getDestinationAllowanceStandardCcy($dateTime, $allowanceStandardInfo);
        if (currency == null) {
            currency = $baseCcy;
        }

        AllowanceResult allowanceResult = new AllowanceResult($dateTime, "88.004", actualAmount, $baseCcy, currency);
        allowanceResult.setConsumeLocation($destination);
        allowanceResult.setDestination($destination);
        allowanceResult.setTravelRouteCode($travelRecord.getTravelRouteCode());

        insert(allowanceResult);
end
```
