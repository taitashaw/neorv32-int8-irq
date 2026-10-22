# Opens the combined block design of build/vivado_bd (made by scripts/build_bd.tcl) on the
# IP Integrator canvas. If scripts/int8_irq_bd_layout.native exists, it sets the block
# positions after the window has its full size (drawing only; the .bd is not changed).
# Test hooks: VIEW_SHOT=<png> takes a screenshot of the X display, VIEW_AUTOQUIT=1 then
# quits, VIEW_EXPORT_LAYOUT=<file> writes the current layout. The plain command sets none.
set root [file normalize [file dirname [info script]]/..]
set rc [catch {
  open_project $root/build/vivado_bd/int8_irq_bd.xpr
  open_bd_design [get_files int8_irq_bd.bd]
} err]
if {$rc} { puts "OPEN_BD_ERROR: $err" } else { puts "OPEN_BD_OK" }
proc finish_bd {} {
  global root
  set lay $root/scripts/int8_irq_bd_layout.native
  if {[file exists $lay]} {
    if {[catch {regenerate_bd_layout -layout_file $lay} e]} { puts "OPEN_BD_LAYOUT_ERROR: $e" } else { puts "OPEN_BD_LAYOUT $lay" }
  }
  if {[info exists ::env(VIEW_EXPORT_LAYOUT)]} {
    if {[catch {write_bd_layout -force -format native $::env(VIEW_EXPORT_LAYOUT)} e]} { puts "EXPORT_ERROR: $e" } else { puts "LAYOUT_EXPORTED" }
  }
  if {[info exists ::env(VIEW_SHOT)]} {
    after 10000 {
      catch {exec import -window root -display $::env(DISPLAY) $::env(VIEW_SHOT)} e
      puts "VIEW_SHOT: $::env(VIEW_SHOT) $e"
      if {[info exists ::env(VIEW_AUTOQUIT)]} { after 1000 exit }
    }
  } elseif {[info exists ::env(VIEW_AUTOQUIT)]} { after 5000 exit }
}
if {!$rc} { after 6000 finish_bd } elseif {[info exists ::env(VIEW_AUTOQUIT)]} { exit }
