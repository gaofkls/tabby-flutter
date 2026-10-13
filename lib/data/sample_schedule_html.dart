/// 教务系统课表页面的真实 HTML 样例。
/// 既是导入页「填示例」的内容，也是解析器的测试夹具。
const sampleScheduleHtml = '''
<table class="table1 table table-striped myTable">
<caption class="text-center push-down-4">
<input type="hidden" class="ksrq" value="2026-10-12">
<input type="hidden" class="jsrq" value="2026-10-18">
<span class="zsj">2026年10月12日-2026年10月18日</span>
<span class="djz">第六周</span>
</caption>
<thead>
<tr>
<th style="width:40px;"></th>
<th style="width:140px;"></th>
<th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th>
<th>星期五</th><th>星期六</th><th>星期日</th>
</tr>
</thead>
<tbody>
<tr><td data-dm="1" rowspan="5">上午</td><td>第1节<br>08:00:00-08:45:00</td><td class="1_1"></td><td class="1_2"></td><td class="1_3" rowspan="4"><b>现代图像处理（1班）</b><br>【邢素霞】(工2-302-1,第1-3,5-9周;)<br></td><td class="1_4"></td><td class="1_5"></td><td class="1_6"></td><td class="1_7"></td></tr>
<tr><td>第2节<br>08:50:00-09:35:00</td><td class="2_1"></td><td class="2_2"></td><td class="2_4"></td><td class="2_5" rowspan="4"><b>新时代中国特色社会主义理论与实践（免选专业通用1班）</b><br>【滕蔓】(良乡B报告厅,第1-9周;)<br></td><td class="2_6"></td><td class="2_7"></td></tr>
<tr><td>第3节<br>09:50:00-10:35:00</td><td class="3_1" rowspan="2"><b>硕士生英语（免选通用3班）</b><br>【孙小清】(工2-203-3,第1-18周;)<br></td><td class="3_2"></td><td class="3_4"></td><td class="3_6"></td><td class="3_7"></td></tr>
<tr><td>第4节<br>10:40:00-11:25:00</td><td class="4_2"></td><td class="4_4"></td><td class="4_6"></td><td class="4_7"></td></tr>
<tr><td>第5节<br>11:30:00-12:15:00</td><td class="5_1"></td><td class="5_2"></td><td class="5_3"></td><td class="5_4"></td><td class="5_6"></td><td class="5_7"></td></tr>
<tr><td data-dm="2" rowspan="5">下午</td><td>第6节<br>13:40:00-14:25:00</td><td class="6_1" rowspan="4"><b>现代控制科学前沿专题（1班）</b><br>【王瑜】(工2-302-2,第1-9周;)<br></td><td class="6_2" rowspan="4"><b>算法分析与设计（1班）</b><br>【张崇】(师服406,第1-9周;)<br></td><td class="6_3"></td><td class="6_4" rowspan="4"><b>随机过程（1班）</b><br>【丛薪蓉】(师服407,第1-8周;)<br></td><td class="6_5"></td><td class="6_6"></td><td class="6_7"></td></tr>
<tr><td>第7节<br>14:30:00-15:15:00</td><td class="7_3"></td><td class="7_5"></td><td class="7_6"></td><td class="7_7"></td></tr>
<tr><td>第8节<br>15:30:00-16:15:00</td><td class="8_3"></td><td class="8_5"></td><td class="8_6"></td><td class="8_7"></td></tr>
<tr><td>第9节<br>16:20:00-17:05:00</td><td class="9_3"></td><td class="9_5"></td><td class="9_6"></td><td class="9_7"></td></tr>
<tr><td>第10节<br>17:10:00-17:55:00</td><td class="10_1"></td><td class="10_2"></td><td class="10_3"></td><td class="10_4"></td><td class="10_5"></td><td class="10_6"></td><td class="10_7"></td></tr>
<tr><td data-dm="3" rowspan="3">晚上</td><td>第11节<br>18:45:00-19:30:00</td><td class="11_1"></td><td class="11_2"></td><td class="11_3"></td><td class="11_4"></td><td class="11_5"></td><td class="11_6"></td><td class="11_7"></td></tr>
<tr><td>第12节<br>19:35:00-20:20:00</td><td class="12_1"></td><td class="12_2"></td><td class="12_3"></td><td class="12_4"></td><td class="12_5"></td><td class="12_6"></td><td class="12_7"></td></tr>
<tr><td>第13节<br>20:25:00-21:10:00</td><td class="13_1"></td><td class="13_2"></td><td class="13_3"></td><td class="13_4"></td><td class="13_5"></td><td class="13_6"></td><td class="13_7"></td></tr>
</tbody>
</table>
''';
