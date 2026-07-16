# real_2.15_仅报销人_行程天数判断扣减

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

function List sort(List array) {
	List list = new ArrayList<>();
	int length = array.size();
	if (length > 0) {
		for (int i = 0; i < length; i++) {
			DateListTravel minimum = null;
			int index = 0;
			for (int j = 0; j < array.size(); j++) {
				if(minimum == null){
					minimum = (DateListTravel)array.get(j);
					index = 0;
				} else {
					DateListTravel arrObj = (DateListTravel)array.get(j);
					List arrObjList = arrObj.getValidDateTimes();
					long arrLong = ((DateTime)arrObjList.get(0)).getMillis();
					List minimumList = minimum.getValidDateTimes();
					long minimumLong = ((DateTime)minimumList.get(0)).getMillis();
					if(arrLong < minimumLong){
						minimum = (DateListTravel)array.get(j);
						index = j;
					}
				}
			}
			array.remove(index);
			list.add(minimum);
		}
	}
	return list;
}

function boolean isContinuousDates(DateTime big, DateTime small, Logger logger) {
	if((big.getMillis() -  small.getMillis()) <= 3600*24*1000){
		return true;
	}
	return false;
}

// 创建全局参数
declare TravelHalfDayKeys
	dateMap : Map // 存储日期集合
	bizCode : String // 标准补贴编码
	feeCode : String // 费用类型编码
end

// 存储每个行程出重后的日期
declare DateListTravel
	travelRecord : TravelRoute
	validDateTimes : List
end

// 存储可以排序的行程
declare DateListTravelList
	travelRouteList : List
end

rule "初始化参数"
    salience 30
    when
        Reimburse(); // 判断是否有单据
    then
		String bizCode="BT"; // 设置标准补贴编码
		String feeCode="BT1"; // 设置费用类型编码
        insert(new TravelHalfDayKeys(new HashMap(), bizCode, feeCode));
end

rule "初始化日期和行程的关系-去重"
   salience 25
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
	then
		if($travelRoutes != null){
			List _travelRouteList = new ArrayList();
			for(Object obj : $travelRoutes){
				TravelRoute route = (TravelRoute)obj;
				List dateTimes = allowanceService.getTripDiffDays(route);
				List newDateTimes = new ArrayList();
				/**循环出差天数 */
				for(Object dt : dateTimes) {
					/**转换成日期对象 */
					DateTime dateTime = (DateTime)dt;
					/**判断日期是否重叠 */
					if(!isDayOverlap($dateMap, $reimEmployee.getUserCode(), dateTime)) {
						newDateTimes.add(dateTime);
					}
				}
				if(newDateTimes.size() > 0){
					_travelRouteList.add(new DateListTravel(route, newDateTimes)); 
				}
			}
			List finalList = sort(_travelRouteList);
			insert(new DateListTravelList(finalList));
		}
end

rule "行程报销人规则计算"
    salience 20
    when
		// 获取变量参数
        TravelHalfDayKeys(
            $dateMap:dateMap, // 获取日期集合
            $bizCode:bizCode, // 获取准补贴编码
            $feeCode:feeCode // 获取费用类型编码
        );
        DateListTravelList(
			$travelRouteList : travelRouteList
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
    then
		DateTime lastEndDay = null;
		int index = 0;
		for(Object obj : $travelRouteList) {
			DateListTravel dateListTravel = (DateListTravel)obj;
			TravelRoute $travelRecord = dateListTravel.getTravelRecord();
			List dateTimes = dateListTravel.getValidDateTimes();
			/** 处理多行程的人天扣减 start */
			logger.info("微步测试行程1111：" + dateTimes);
			if(index > 0){
				/**缓存上个行程的最后一天 */
				DateListTravel lastTravel = (DateListTravel)$travelRouteList.get(index - 1);
				logger.info("微步测试行程211：" + lastTravel);
				List lastDateTimes = lastTravel.getValidDateTimes();
				if(lastDateTimes.size() > 0){
					lastEndDay = (DateTime)lastDateTimes.get(lastDateTimes.size() - 1);
				} else {
					lastEndDay = null;
				}
				logger.info("微步测试行程221：" + lastEndDay);
			}
			/**扣减逻辑：与下一个行程不连续时，如果日期天数大于1，需要-1
			*/
			DateTime nextFirst = null;
			/** 不是最后一个行程的时候，取下一个行程的首日 */
			if(index + 1 < $travelRouteList.size()){
				DateListTravel nextTravel = (DateListTravel)$travelRouteList.get(index + 1);
				List nextDateTimes = nextTravel.getValidDateTimes();
				nextFirst = (DateTime)nextDateTimes.get(0);
			}
			/**并且最后一日和下一个行程第一日不相邻(或下个行程为空)  此时日期需要扣除最后一个*/
			if(nextFirst == null || !isContinuousDates(nextFirst, (DateTime)dateTimes.get(dateTimes.size() - 1), logger)){
				/**不承接上一个行程的，如果日期只有一天不扣减 */
				logger.info("微步-上一行程最后一日：" + lastEndDay + "   " + dateTimes.size());
				if(dateTimes.size() > 1){
					dateTimes.remove(dateTimes.size() - 1);
				}
			}
			logger.info("微步处理多行程的人天扣减3：" + dateTimes.size() + "  " + $travelRecord);
			/** 处理多行程的人天扣减 end */
			/**获取币种 */
			String currency = "";
			AllowanceStandardInfo allowanceStandardInfo = null;
			for(Object _allowanceStandardInfo : $travelRecord.getAllowanceStandardInfos()){
				AllowanceStandardInfo $allowanceStandardInfo = (AllowanceStandardInfo)_allowanceStandardInfo;
				if($allowanceStandardInfo.getRuleBizCode().equals($bizCode)){
					allowanceStandardInfo = $allowanceStandardInfo;
					Map map = allowanceStandardInfo.getStandardMap();
					currency = ((AllowanceStandard)map.get($bizCode + "DESTINATION")).getCurrency();
				}
			}
			logger.info("微步测试行程3 补贴币种是：" + currency);
			DateTime $startDate = $travelRecord.getStartDate();
			DateTime $endDate = $travelRecord.getEndDate();
			String $destination = $travelRecord.getDestination();
			/**获取报销人补贴金额 */
			BigDecimal amount = new BigDecimal("0");
			if(allowanceStandardInfo != null && dateTimes.size()>0){
				BigDecimal allowanceAmount = allowanceService.getDestinationAllowanceStandard(
					(DateTime)dateTimes.get(0), 
					allowanceStandardInfo
				);
				logger.info("微步测试行程4：" + allowanceAmount);
				amount = allowanceAmount.multiply(new BigDecimal(dateTimes.size()));
				$startDate = dateTimes.get(0);
				if(dateTimes.size()>1){
					$endDate = dateTimes.get(dateTimes.size() - 1);
				} else {
					$endDate = $startDate;
				}
			}
			logger.info("微步测试行程5：" + amount);
			/**返回补贴结果 */
			AllowanceResult allowanceResult = new AllowanceResult($startDate, $endDate, $feeCode, amount, currency,currency);
            /**设置消费城市 */
            allowanceResult.setConsumeLocation($destination);
            insert(allowanceResult);
			
			index = index + 1;
		}
end
```
