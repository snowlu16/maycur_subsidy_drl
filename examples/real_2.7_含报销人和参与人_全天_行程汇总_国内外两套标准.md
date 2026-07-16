# real_2.7_含报销人和参与人_全天_行程汇总_国内外两套标准

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
	innerBizCode : String // 国内标准补贴编码
	innerFeeCode : String // 国内费用类型编码
    outerBizCode: String // 国外标准补贴编码
    outerFeeCode: String // 国外费用类型编码
end

rule "初始化参数"
    salience 30
    when
        Reimburse(); // 判断是否有单据
    then
		String innerBizCode = "footAllowance"; // 设置国内标准补贴编码
		String innerFeeCode = "12345"; // 设置国内费用类型编码
        String outerBizCode = "test123"; // 设置国外标准补贴编码
        String outerFeeCode = "1014"; // 设置国外费用类型编码
        insert(new TravelHalfDayKeys(new HashMap(), innerBizCode, innerFeeCode, outerBizCode, outerFeeCode));
end

rule "报销人和参与人行程费用国内补贴金额规则"
    salience 20
    when
        // 获取变量参数
        TravelHalfDayKeys(
            $dateMap:dateMap, // 获取日期集合
            $innerBizCode:innerBizCode, // 获取国内准补贴编码
            $innerFeeCode:innerFeeCode // 获取国内费用类型编码
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
        // 判断是否是国内
        eval($destination.contains("domestic"));
        // 获取补贴信息
		$allowanceStandardInfo : AllowanceStandardInfo(
			$innerBizCode.equals(ruleBizCode) // 补贴标准编码
		) from $allowanceStandardInfos;
        // 判断补贴标准是否存在
        $map : Map(get($innerBizCode + "DESTINATION") != null) from $allowanceStandardInfo.getStandardMap();
    then

        /**设置补贴总金额 */
		BigDecimal amount = BigDecimal.ZERO;

        /**获取根据行程的开始结束时间计算出差天数**/
        List dateTimes = allowanceService.getTripDiffDays($travelRecord);

        /**循环出差天数 */
        for(Object obj : dateTimes) {
            
            /**转换成日期对象 */
            DateTime dateTime = (DateTime)obj;

            /**====== 计算报销人补贴金额 ======*/
            /**获取报销人补贴金额 */
            BigDecimal allowanceAmount = allowanceService.getDestinationAllowanceStandard(
                dateTime, 
                $allowanceStandardInfo
            );

            logger.info("补贴报销人行程日期为" + dateTime + ",补贴报销人编号为" + $reimEmployee.getUserCode() + ",补贴标准金额为" + allowanceAmount + ",补贴标准编码为" + $innerBizCode);

            /**判断报销人行程日期是否重叠 */
            if(!isDayOverlap($dateMap, $reimEmployee.getUserCode() + $innerBizCode, dateTime)) {
                amount = amount.add(allowanceAmount);
            }

            /**====== 计算参与人补贴金额 ======*/
            /**判断是否有参与人 */
            if ($travelPartnerInfo != null) {

                /**循环参与人信息列表 */
                for(TravelPartner travelPartner : $travelPartnerInfo.getInternalTravelPartner) {

                    /**获取补贴标准金额 */
                    BigDecimal partnerAllowanceAmount = allowanceService.getDestinationPartnerAllowanceStandard(
                        dateTime,
                        $partnerAllowanceStandardInfos,
                        travelPartner,
                        $innerBizCode
                    );

                    logger.info("补贴参与人行程日期为" + dateTime + ",补贴参与人编号为" + travelPartner.getUserCode() + ",补贴标准金额为" + partnerAllowanceAmount + ",补贴标准编码为" + $innerBizCode);

                    /**判断日期是否重叠 */
                    if(!isDayOverlap($dateMap, travelPartner.getUserCode() + $innerBizCode, dateTime)) {
                        amount = amount.add(partnerAllowanceAmount);
                    }
                }

            }

        }

        /**判断出差补助是否大于零 */
        if(amount.compareTo(BigDecimal.ZERO) == 1) {

            /**获取币种 */
            String currency = ((AllowanceStandard)$map.get($innerBizCode + "DESTINATION")).getCurrency();

            /**返回补贴结果 */
            AllowanceResult allowanceResult = new AllowanceResult($startDate, $endDate, $innerFeeCode, amount, currency, currency);
            /**设置消费城市 */
            allowanceResult.setConsumeLocation($destination);

            insert(allowanceResult);
        }
end

rule "报销人和参与人行程费用国外补贴金额规则"
    salience 10
    when
        // 获取变量参数
        TravelHalfDayKeys(
            $dateMap:dateMap, // 获取日期集合
            $outerBizCode:outerBizCode, // 获取国外准补贴编码
            $outerFeeCode:outerFeeCode // 获取国外费用类型编码
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
        // 判断是否是国外
        eval($destination.contains("abroad"));
        // 获取补贴信息
		$allowanceStandardInfo : AllowanceStandardInfo(
			$outerBizCode.equals(ruleBizCode) // 补贴标准编码
		) from $allowanceStandardInfos;
        // 判断补贴标准是否存在
        $map : Map(get($outerBizCode + "DESTINATION") != null) from $allowanceStandardInfo.getStandardMap();
    then

        /**设置补贴总金额 */
		BigDecimal amount = BigDecimal.ZERO;

        /**获取根据行程的开始结束时间计算出差天数**/
        List dateTimes = allowanceService.getTripDiffDays($travelRecord);

        /**循环出差天数 */
        for(Object obj : dateTimes) {
            
            /**转换成日期对象 */
            DateTime dateTime = (DateTime)obj;

            /**====== 计算报销人补贴金额 ======*/
            /**获取报销人补贴金额 */
            BigDecimal allowanceAmount = allowanceService.getDestinationAllowanceStandard(
                dateTime, 
                $allowanceStandardInfo
            );

            logger.info("补贴报销人行程日期为" + dateTime + ",补贴报销人编号为" + $reimEmployee.getUserCode() + ",补贴标准金额为" + allowanceAmount + ",补贴标准编码为" + $outerBizCode);

            /**判断报销人行程日期是否重叠 */
            if(!isDayOverlap($dateMap, $reimEmployee.getUserCode() + $outerBizCode, dateTime)) {
                amount = amount.add(allowanceAmount);
            }

            /**====== 计算参与人补贴金额 ======*/
            /**判断是否有参与人 */
            if ($travelPartnerInfo != null) {
                
                /**循环参与人信息列表 */
                for(TravelPartner travelPartner : $travelPartnerInfo.getInternalTravelPartner) {

                    /**获取补贴标准金额 */
                    BigDecimal partnerAllowanceAmount = allowanceService.getDestinationPartnerAllowanceStandard(
                        dateTime,
                        $partnerAllowanceStandardInfos,
                        travelPartner,
                        $outerBizCode
                    );

                    logger.info("补贴参与人行程日期为" + dateTime + ",补贴参与人编号为" + travelPartner.getUserCode() + ",补贴标准金额为" + partnerAllowanceAmount + ",补贴标准编码为" + $outerBizCode);

                    /**判断日期是否重叠 */
                    if(!isDayOverlap($dateMap, travelPartner.getUserCode() + $outerBizCode, dateTime)) {
                        amount = amount.add(partnerAllowanceAmount);
                    }
                }

            }

        }

        /**判断出差补助是否大于零 */
        if(amount.compareTo(BigDecimal.ZERO) == 1) {

            /**获取币种 */
            String currency = ((AllowanceStandard)$map.get($outerBizCode + "DESTINATION")).getCurrency();

            /**返回补贴结果 */
            AllowanceResult allowanceResult = new AllowanceResult($startDate, $endDate, $outerFeeCode, amount, currency, currency);
            /**设置消费城市 */
            allowanceResult.setConsumeLocation($destination);

            insert(allowanceResult);
        }
end
```
