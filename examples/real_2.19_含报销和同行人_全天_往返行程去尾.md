# real_2.19_含报销和同行人_全天_往返行程去尾

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
	bizCode : String // 标准补贴编码
	feeCode : String // 费用类型编码
    ratio : BigDecimal // 比率
end

rule "初始化参数"
    salience 30
    when
        Reimburse(); // 判断是否有单据
    then
		String bizCode="footAllowance"; // 设置标准补贴编码
		String feeCode="12345"; // 设置费用类型编码
        BigDecimal ratio = BigDecimal.valueOf(0); // 设置同天往返补贴金额比率
        insert(new TravelHalfDayKeys(new HashMap(), bizCode, feeCode, ratio));
end

rule "报销人和参与人行程费用规则计算"
    salience 10
    when
        // 获取变量参数
        TravelHalfDayKeys(
            $dateMap:dateMap, // 获取日期集合
            $bizCode:bizCode, // 获取准补贴编码
            $feeCode:feeCode, // 获取费用类型编码
            $ratio:ratio // 获取比率
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
        // 获取补贴信息
		$allowanceStandardInfo : AllowanceStandardInfo(
			$bizCode.equals(ruleBizCode) // 补贴标准编码
		) from $allowanceStandardInfos;
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

            logger.info("补贴报销人行程日期为" + dateTime + ",补贴报销人编号为" + $reimEmployee.getUserCode() + ",补贴标准金额为" + allowanceAmount);

            /**判断报销人行程日期是否重叠 */
            if(!isDayOverlap($dateMap, $reimEmployee.getUserCode(), dateTime)) {
                /**判断是否同天往返 */
                if(dateTimes.size() == 1) {
                    amount = amount.add(allowanceAmount.multiply($ratio));
                /** 判断时间是否为结束时间不计算补贴金额 **/    
                } else if(!dateTime.withTimeAtStartOfDay().isEqual($endDate.withTimeAtStartOfDay())) {
                    amount = amount.add(allowanceAmount);
                }
                
            }

            /**====== 计算参与人补贴金额 ======*/
            
            if ($travelPartnerInfo != null) {
                
                /**循环参与人信息列表 */
                for(TravelPartner travelPartner : $travelPartnerInfo.getInternalTravelPartner) {

                    /**获取补贴标准金额 */
                    BigDecimal partnerAllowanceAmount = allowanceService.getDestinationPartnerAllowanceStandard(
                        dateTime,
                        $partnerAllowanceStandardInfos,
                        travelPartner,
                        $bizCode
                    );

                    logger.info("补贴参与人行程日期为" + dateTime + ",补贴参与人编号为" + travelPartner.getUserCode() + ",补贴标准金额为" + partnerAllowanceAmount);

                    /**判断日期是否重叠 */
                    if(!isDayOverlap($dateMap, travelPartner.getUserCode(), dateTime)) {
                        /**判断是否同天往返 */
                        if(dateTimes.size() == 1) {
                            amount = amount.add(partnerAllowanceAmount.multiply($ratio));
                        /** 判断时间是否为结束时间不计算补贴金额 **/    
                        } else if(!dateTime.withTimeAtStartOfDay().isEqual($endDate.withTimeAtStartOfDay())) {
                            amount = amount.add(partnerAllowanceAmount);
                        }
                        
                    }
                }
            
            }

        }

        /**判断出差补助是否大于零 */
      

            /**返回补贴结果 */
            AllowanceResult allowanceResult = new AllowanceResult($startDate, $endDate, $feeCode, amount, $baseCcy, $collectionCcy);
            /**设置消费城市 */
            allowanceResult.setConsumeLocation($destination);

            insert(allowanceResult);
        
end
```
