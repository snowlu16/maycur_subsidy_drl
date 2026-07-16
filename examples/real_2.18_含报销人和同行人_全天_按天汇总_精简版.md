# real_2.18_含报销人和同行人_全天_按天汇总_精简版

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

dialect  "mvel"

/**
    判断日期是否重叠
    @param map 存入多个用户的行程日期集合
    @param userCode 内部员工编码
    @param dateTime 行程某天的日期
 */
function boolean isDayOverlap(Map map, String userCode, DateTime dateTime) {
    // 存储日期列表
    List days = null;
    // 判断当前用户是否存有日期列表
    if(map.get(userCode) == null) {
        days = new ArrayList();
    } else {
        days = (List)map.get(userCode);
    }
    // 获取日期
    String day = dateTime.toString("yyyy-MM-dd");
    // 判断日期是否存在于日期列表中
    if(!days.contains(day)) {
        days.add(day);
        map.put(userCode, days);
        return false;
    }
    return true;
}

// 创建全局参数
declare TravelHalfDayKeys
	dateMap : Map // 存储日期集合
	firstBizCode : String // 第一个标准补贴编码
	firstFeeCode : String // 第一个费用类型编码

end

rule "初始化参数"
    salience 30
    when
        Reimburse(); // 判断是否有单据
    then
	String firstBizCode = "footAllowance"; // 设置第一个标准补贴编码
		String firstFeeCode = "12345"; // 设置第一个费用类型编码

        insert(new TravelHalfDayKeys(new HashMap(), firstBizCode, firstFeeCode));
end

rule "报销人和参与人行程费用第一个补贴金额规则"
    salience 20
    when
        // 获取变量参数
        TravelHalfDayKeys(
            $dateMap:dateMap, // 获取日期集合
            $firstBizCode:firstBizCode, // 获取准补贴编码
            $firstFeeCode:firstFeeCode // 获取费用类型编码
        );
        // 获取单据
        Reimburse(
            $travelRoutes:travelRoutes, // 行程信息
            $reimEmployee:reimEmployee, // 报销人信息
            $collectionCcy:collectionCcy, // 收款币种
            $baseCcy:baseCcy // 本币
        );
        // 获取行程信息
        $travelRecord : TravelRoute(
            $startDate:startDate, // 行程出发时间
            $endDate:endDate, // 行程返回时间
            $destination:destination, // 行程目的地
            $allowanceStandardInfos:allowanceStandardInfos, // 报销人补贴标准信息
            $travelPartnerInfo:travelPartnerInfo, // 参与人信息
            $partnerAllowanceStandardInfos:partnerAllowanceStandardInfos // 参与人补贴标准信息
        ) from $travelRoutes;
        // 根据行程的开始结束时间计算出差天数
        $dateTime : DateTime() from allowanceService.getTripDiffDays($travelRecord);
        // 获取补贴信息
        $allowanceStandardInfo : AllowanceStandardInfo(
            $firstBizCode.equals(ruleBizCode) // 补贴标准编码
        ) from $allowanceStandardInfos;
    then
        /**设置补贴总金额 */
		BigDecimal amount = BigDecimal.ZERO;

        /**判断是否有报销人信息 */
        if($reimEmployee != null) {

            /**获取报销人补贴金额 */
            BigDecimal allowanceAmount = allowanceService.getDestinationAllowanceStandard(
                $dateTime, 
                $allowanceStandardInfo
            );
    
            /**判断报销人行程日期是否重叠 */
            if(!isDayOverlap($dateMap, $reimEmployee.getUserCode() + $firstBizCode, $dateTime)) {
    
                amount = amount.add(allowanceAmount);
                
            }
    
            logger.info("补贴报销人行程日期为" + $dateTime + ",补贴报销人编号为" + $reimEmployee.getUserCode() + ",补贴标准金额为" + allowanceAmount + $firstBizCode);
        }

        /**判断是否有参与人 */
        if ($travelPartnerInfo != null) {
                
            /**循环参与人信息列表 */
            for(TravelPartner travelPartner : $travelPartnerInfo.getInternalTravelPartner) {

                /**获取参与人补贴标准金额 */
                BigDecimal partnerAllowanceAmount = allowanceService.getDestinationPartnerAllowanceStandard(
                    $dateTime,
                    $partnerAllowanceStandardInfos,
                    travelPartner,
                    $firstBizCode
                );

                logger.info("补贴参与人行程日期为" + $dateTime + ",补贴参与人编号为" + travelPartner.getUserCode() + ",补贴标准金额为" + partnerAllowanceAmount + $firstBizCode);

                /**判断日期是否重叠 */
                if(!isDayOverlap($dateMap, travelPartner.getUserCode() + $firstBizCode, $dateTime)) {
                    amount = amount.add(partnerAllowanceAmount);
                }
            }
        
        }

        /**判断出差补助是否大于零 */
        if(amount.compareTo(BigDecimal.ZERO) == 1) {

            insert(new AllowanceResult($dateTime, $firstFeeCode, amount, $baseCcy, $collectionCcy, $destination));
            
        }
end
```
