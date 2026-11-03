# TD's documented MultiSeed flow separates route and fix_hold. The integrated
# route crashed after its Hold Fix stage; reuse the saved placement checkpoint.
source ./settings.cfg
import_device $device_name -package $package_name
open_project ${prj_name}.prj -noanalyze
import_db ${prj_name}_place.db
set_param route fix_hold off
route
export_db ${prj_name}_before_hold.db
fix_hold
set_param route fix_hold on
update_timing -mode final
report_timing_status -file ${prj_name}_phy.ts
report_timing_summary -file ${prj_name}_pr.timing
report_area -io_info -file ${prj_name}_phy.area
export_db ${prj_name}_pr.db
bitgen -bit ${prj_name}.bit
