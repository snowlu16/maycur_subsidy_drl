# real_1.4_含报销人和参与人_半天_每人每天一条

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

/*
	判断日期是否半天或重叠
    @param map 存入多个用户的行程日期集合
    @param userCode 内部员工编码
    @param day 行程某天的日期
    @param startDate 行程出发日期
    @param endDate 行程返回日期
    @return -1表示重叠,0表示半天,1表示全天
 */
function int isDayHalveOrOverlap(Map map, String userCode, DateTime day, DateTime startDate, DateTime endDate) {
    // 标识符
    int flag = 1;
    // 存储日期列表
    List days = null;
    // 判断当前用户是否存有日期列表
    if(map.get(userCode) == null) {
        days = new ArrayList();
    } else {
        days = (List)map.get(userCode);
    }
    // 设置上午时间
    String amDay = day.toString("yyyy-MM-dd") + "am";
    // 设置下午时间
	String pmDay = day.toString("yyyy-MM-dd") + "pm";
    // 判断是否是行程的出发时间
	if(day.getYear() == startDate.getYear() 
		&& day.getMonthOfYear() == startDate.getMonthOfYear() 
		&& day.getDayOfMonth() == startDate.getDayOfMonth()) {
		// 出发时间在12点后(含)，当天为半天
		if(startDate.getHourOfDay() >= 12) {
			// 判断下午的日期是否存在于日期列表中
            if(days.contains(pmDay)) {
            	return -1;
            }
            days.add(pmDay);
            map.put(userCode, days);
			return 0;
		}
	}
    // 判断是否是行程的返回时间
    if(day.getYear() == endDate.getYear() 
		&& day.getMonthOfYear() == endDate.getMonthOfYear() 
		&& day.getDayOfMonth() == endDate.getDayOfMonth()) {
		// 返回时间12点前，当天为半天
		if(endDate.getHourOfDay() < 12) {
			// 判断上午的日期是否存在于日期列表中
            if(days.contains(amDay)) {
            	return -1;
            }
            days.add(amDay);
            map.put(userCode, days);
			return 0;
		// 返回时间(含)12点，当天为半天
		} else if (endDate.getHourOfDay() == 12 
			&& endDate.getMinuteOfHour() == 0) {
			// 判断上午的日期是否存在于日期列表中
            if(days.contains(amDay)) {
            	return -1;
            }
            days.add(amDay);
            map.put(userCode, days);
			return 0;
		}
	}
    // 判断上午和下午是否在日期列表中
    if(days.contains(amDay) && days.contains(pmDay)) {
        return -1;
    } else {
        // 判断上午的日期是否存在于日期列表中
        if(days.contains(amDay)) {
            flag = 0;
        } else {
            days.add(amDay);
        }
        // 判断下午的日期是否存在于日期列表中
        if(days.contains(pmDay)) {
                flag = 0;
        } else {
            days.add(pmDay);
        }
    }
	map.put(userCode, days);
    return flag;
}

// 创建全局参数
declare TravelHalfDayKeys
	dateMap : Map // 存储日期集合
	bizCode : String // 标准补贴编码
	feeCode : String // 费用类型编码
end

rule "初始化参数"
    salience 30
    when
        Reimburse(); // 判断是否有单据
    then
		String bizCode="footAllowance"; // 设置标准补贴编码
		String feeCode="BT"; // 设置费用类型编码
        insert(new TravelHalfDayKeys(new HashMap(), bizCode, feeCode));
end

rule "报销人费用规则计算"
    salience 20
   when
        // 获取变量参数
        TravelHalfDayKeys(
            $dateMap:dateMap, // 获取日期集合
            $bizCode:bizCode, // 获取准补贴编码
            $feeCode:feeCode // 获取费用类型编码
        );
        // 获取单据
        Reimburse(
            $travelRoutes:travelRoutes, // 行程信息
            $reimEmployee:reimEmployee, // 报销人信息
            $collectionCcy:collectionCcy, // 收款币种
            $baseCcy:baseCcy // 本币
        );
        // 判断是否有报销人信息
        eval($reimEmployee != null);
        // 获取行程信息
        $travelRecord : TravelRoute(
            $startDate:startDate, // 行程出发时间
            $endDate:endDate, // 行程返回时间
            $destination:destination, // 行程目的地
	        $travelRouteCode:travelRouteCode,//行程code
            $allowanceStandardInfos:allowanceStandardInfos // 报销人补贴标准信息
        ) from $travelRoutes;
        // 根据行程的开始结束时间计算出差天数
        $dateTime : DateTime() from allowanceService.getTripDiffDays($travelRecord);
        // 获取补贴信息
		$allowanceStandardInfo : AllowanceStandardInfo(
			$bizCode.equals(ruleBizCode) // 补贴标准编码
		) from $allowanceStandardInfos;
    then

        // 获取报销人补贴金额
        BigDecimal allowanceAmount = allowanceService.getDestinationAllowanceStandard(
           $dateTime, 
           $allowanceStandardInfo
        );

        // 获取行程中的时间是否有半天或重叠
        int state = isDayHalveOrOverlap(
            $dateMap, 
            $reimEmployee.getUserCode(), 
            $dateTime, 
            $startDate, 
            $endDate
        );

        logger.info("补贴测试行程日期为" + $dateTime +",补贴测试报销人编号为" + $reimEmployee.getUserCode() + ",补贴标准金额为" + allowanceAmount  + ",补贴测试日期判断状态为" + state);

        String currency = allowanceService.getDestinationAllowanceStandardCcy($startDate, $allowanceStandardInfo);

        if(state == 1) {
	
	        AllowanceResult result = new AllowanceResult(
                $dateTime, 
                $feeCode, 
                allowanceAmount,
                currency, 
                currency, 
                $destination
            );
	        result.setTravelRouteCode($travelRouteCode);
	
            insert(result);
	
        } else if (state == 0) {

            AllowanceResult result=new AllowanceResult(
                $dateTime, 
                $feeCode, 
                allowanceAmount.divide(BigDecimal.valueOf(2)),
                currency, 
                currency, 
                $destination
            );
	        result.setTravelRouteCode($travelRouteCode);

            insert(result);
        }
end

rule "参与人行程费用规则"
    salience 10
    when
        // 获取变量参数
        TravelHalfDayKeys(
            $dateMap:dateMap, // 获取日期集合
            $bizCode:bizCode, // 获取准补贴编码
            $feeCode:feeCode // 获取费用类型编码
        );
        // 获取单据
        Reimburse(
            $travelRoutes:travelRoutes, // 行程信息
            $collectionCcy:collectionCcy, // 收款币种
            $baseCcy:baseCcy // 本币
        );
        // 获取行程信息
        $travelRecord : TravelRoute(
            $startDate:startDate, // 行程出发时间
            $endDate:endDate, // 行程返回时间
            $destination:destination, // 行程目的地
            $travelRouteCode:travelRouteCode,//行程code
            $travelPartnerInfo:travelPartnerInfo, // 参与人信息
            $partnerAllowanceStandardInfos:partnerAllowanceStandardInfos // 参与人补贴标准信息
        ) from $travelRoutes;
        // 判断是否有参与人
        eval($travelPartnerInfo != null);
        // 根据行程的开始结束时间计算出差天数
        $dateTime : DateTime() from allowanceService.getTripDiffDays($travelRecord);
        // 获取内部同行人
        $travelPartner : TravelPartner() from $travelPartnerInfo.getInternalTravelPartner();
        // 获取补贴信息
		$partnerAllowanceStandardInfo : AllowanceStandardInfo(
			$bizCode.equals(ruleBizCode) // 补贴标准编码
		) from $partnerAllowanceStandardInfos;
    then
        /**获取参与人补贴标准金额 */
        BigDecimal partnerAllowanceAmount = allowanceService.getDestinationPartnerAllowanceStandard(
            $dateTime,
            $partnerAllowanceStandardInfos,
            $travelPartner,
            $bizCode
        );

        // 获取行程中的时间是否有半天或重叠
        int state = isDayHalveOrOverlap(
            $dateMap, 
            $travelPartner.getUserCode(), 
            $dateTime, 
            $startDate, 
            $endDate
        );

        logger.info("补贴参与人行程日期为" + $dateTime + ",补贴参与人编号为" + $travelPartner.getUserCode() + ",补贴标准金额为" + partnerAllowanceAmount + ",补贴测试日期判断状态为" + state);

        String currency = allowanceService.getDestinationAllowanceStandardCcy($endDate, $partnerAllowanceStandardInfo);

        if(state == 1) {
	
	        AllowanceResult result = new AllowanceResult(
                $dateTime, 
                $feeCode, 
                partnerAllowanceAmount,
                currency, 
                currency, 
                $destination
            );
	        result.setTravelRouteCode($travelRouteCode);
	
            insert(result);
	
        } else if (state == 0) {

            AllowanceResult result=new AllowanceResult(
                $dateTime, 
                $feeCode, 
                partnerAllowanceAmount.divide(BigDecimal.valueOf(2)),
                currency, 
                currency, 
                $destination
            );
	        result.setTravelRouteCode($travelRouteCode);

            insert(result);
        }
end
```
