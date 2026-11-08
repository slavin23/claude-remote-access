// =====================================================================
//  Scene Switch Cover  -  ESP32 rocker cover for a US single-gang toggle
// =====================================================================
//  Locks a standard toggle light switch in the ON position (so smart
//  bulbs always have power) and puts a printed rocker in front of it.
//  Pressing the top or bottom of the rocker clicks a tactile switch
//  wired to an ESP32, which fires a Home Assistant scene.
//
//  Parts (set `part` below, or use -D part="..." on the command line):
//    "base"     - flat plate that screws onto the real switch
//    "shell"    - cover housing that snaps over the base
//    "rocker"   - the paddle you press
//    "assembly" - exploded preview, not for printing
//    "assembled"- on-the-wall preview, not for printing
//
//  All dimensions in millimetres. Units stay metric; US plate sizes are
//  converted from inches.
// =====================================================================

part = "assembly";   // [base, shell, rocker, assembly]

/* ---------------- Standard US single-gang toggle plate ---------------- */
plate_w        = 69.85;    // 2.75"
plate_h        = 114.3;    // 4.50"
screw_spacing  = 60.33;    // 2.375" centre to centre
toggle_slot_w  = 10.6;     // 0.406" + clearance
toggle_slot_h  = 24.2;     // 0.938" + clearance

/* ---------------- Base plate ---------------- */
base_t         = 4.5;      // total thickness
base_recess    = 2.0;      // hollow back so it clears the switch yoke ears
base_rim       = 3.0;      // width of the rim that touches the wall
screw_d        = 3.8;      // #6-32 clearance
screw_head_d   = 7.6;      // #6-32 flat-head countersink diameter
toggle_keeper  = true;     // block under the toggle so it can't be flipped OFF

/* ---------------- Electronics ---------------- */
// Seeed XIAO ESP32-C6 (21 x 17.5 mm). Also fits XIAO ESP32-C3 / S3.
esp_w = 18.2;  esp_l = 21.8;
esp_x = -21;   esp_y = -43;       // board centre on the base
// LiPo pouch cell 803040 (8 x 30 x 40 mm, 1000 mAh) laid sideways across the
// top of the plate. Also fits 603040 (~700 mAh) or 103040 (~1200 mAh, 10 mm).
// The corral is open on the right so the protection board / leads can stick out.
batt_w = 41;    batt_l = 30.8;     // inner size: X (long side) x Y
batt_x = -12.1; batt_y = 39.6;
// 6 x 6 mm tactile switches (4.3 mm tall version)
tact_body      = 6.3;
tact_h_total   = 4.3;      // body + plunger; change if yours are 5 or 7 mm
tact_x         = 20;       // switches sit beside the toggle, on the right
tact_y         = 22;       // +/- from centre (top / bottom)
pillar_top     = 17.5;     // height above the wall
pocket_depth   = 1.5;

/* ---------------- Shell ---------------- */
depth          = 27;       // how far the cover sticks out from the wall
wall           = 2.0;
front_t        = 2.4;
fit_clear      = 0.25;     // gap between base edge and shell wall
corner_r       = 3;
snap_bump      = 0.5;      // snap ridge height
usb_hole       = true;     // charge port opening in the bottom edge

/* ---------------- Rocker ---------------- */
rocker_w       = 50;
rocker_h       = 80;
rocker_t       = 3;
rocker_gap     = 0.5;      // clearance around the rocker in its opening
hinge_reach    = 27;       // hinge bar half-length (behind the front wall)
pin_d          = 3.0;
pin_len        = 2.5;
nub_gap        = 0.3;      // free play before the switch clicks

$fn = 48;

/* ---------------- Derived ---------------- */
in_w  = plate_w + 2*fit_clear;
in_h  = plate_h + 2*fit_clear;
out_w = in_w + 2*wall;
out_h = in_h + 2*wall;
rocker_back  = depth - rocker_t;          // z of rocker back face
hinge_z0     = rocker_back - 3;           // hinge bar bottom
pin_z        = rocker_back - 1.5;         // pin axis
switch_top   = pillar_top - pocket_depth + tact_h_total;
pivot_x0     = hinge_reach + 0.3;         // pivot block inner face
pivot_x1     = in_w/2 - 0.5;

/* ======================= helpers ======================= */
module rrect(w, h, r, t) {
    linear_extrude(t)
        offset(r) square([w - 2*r, h - 2*r], center = true);
}

/* ======================= BASE ======================= */
module base() {
    difference() {
        union() {
            // plate with hollow back
            difference() {
                rrect(plate_w, plate_h, 1.5, base_t);
                translate([0,0,-0.01])
                    rrect(plate_w - 2*base_rim, plate_h - 2*base_rim, 1, base_recess);
            }
            // snap ridges on the long edges
            for (sx = [-1, 1], sy = [-1, 1])
                translate([sx*plate_w/2, sy*35, base_t - 1.6])
                    rotate([90,0,0]) cylinder(r = snap_bump, h = 14, center = true, $fn = 16);

            // switch pillars
            for (sy = [-1, 1])
                translate([tact_x, sy*tact_y, 0])
                    difference() {
                        translate([-5, -5, 0]) cube([10, 10, pillar_top]);
                        // switch pocket
                        translate([-tact_body/2, -tact_body/2, pillar_top - pocket_depth])
                            cube([tact_body, tact_body, 5]);
                        // leg / wire slots on two sides
                        translate([-6, -1.75, pillar_top - 4]) cube([12, 3.5, 5]);
                        // wire channel down the inside of the pillar
                        translate([-6, -1.5, base_t]) cube([4, 3, pillar_top]);
                    }

            // ESP32 cradle: two rails with a 1 mm ledge the board edges rest on
            // (keeps the XIAO's bottom-side battery pads off the plate)
            translate([esp_x, esp_y, base_t])
                for (sx = [-1, 1]) mirror([sx < 0 ? 1 : 0, 0, 0])
                    difference() {
                        translate([esp_w/2 - 1, -esp_l/2, 0]) cube([3, esp_l, 4.2]);
                        translate([esp_w/2 - 1.1, -esp_l/2 - 1, 2]) cube([1.1, esp_l + 2, 5]);
                    }
            // board end stop (top end; USB end faces down, open)
            translate([esp_x - esp_w/2, esp_y + esp_l/2 + 0.2, base_t])
                cube([esp_w, 1.5, 4.2]);

            // battery corral (3 walls, open toward the centre for the leads)
            translate([batt_x, batt_y, base_t])
                difference() {
                    translate([-batt_w/2 - 1.2, -batt_l/2 - 1.2, 0])
                        cube([batt_w + 1.2, batt_l + 2.4, 3]);
                    translate([-batt_w/2, -batt_l/2, -1]) cube([batt_w + 1, batt_l, 5]);
                }

            // keeper: stops the real toggle being pushed down to OFF
            if (toggle_keeper)
                translate([-4, -toggle_slot_h/2 - 6, base_t - 0.01])
                    cube([8, 5, 8]);
        }
        // toggle opening
        translate([0, 0, -1])
            rrect(toggle_slot_w, toggle_slot_h, 1.5, base_t + 2);
        // countersunk #6-32 screw holes
        for (sy = [-1, 1])
            translate([0, sy*screw_spacing/2, 0]) {
                translate([0,0,-1]) cylinder(d = screw_d, h = base_t + 2);
                translate([0,0, base_t - (screw_head_d - screw_d)/2 + 0.01])
                    cylinder(d1 = screw_d, d2 = screw_head_d, h = (screw_head_d - screw_d)/2);
            }
    }
}

/* ======================= SHELL ======================= */
module shell() {
    difference() {
        union() {
            difference() {
                // outer body with a softened front edge
                hull() {
                    rrect(out_w, out_h, corner_r, depth - 1);
                    translate([0,0,depth - 1]) rrect(out_w - 2, out_h - 2, corner_r - 1, 1);
                }
                // hollow interior, open at the back
                translate([0,0,-0.01]) rrect(in_w, in_h, 1.6, depth - front_t);
            }
            // pivot blocks that hold the rocker pins
            for (sx = [-1, 1])
                translate([sx > 0 ? pivot_x0 : -pivot_x1, -5, hinge_z0 - 2.5])
                    cube([pivot_x1 - pivot_x0, 10, depth - front_t - (hinge_z0 - 2.5) + 0.01]);
        }
        // rocker opening
        translate([0,0,depth - front_t - 1])
            rrect(rocker_w + 2*rocker_gap, rocker_h + 2*rocker_gap, 2.5, front_t + 2);
        // pin slots: open toward the back, slightly pinched so the pins snap in
        for (sx = [-1, 1])
            translate([sx*(pivot_x0 + pin_len/2 + 0.1), 0, 0]) {
                translate([0, 0, pin_z]) rotate([0,90,0])
                    cylinder(d = pin_d + 0.3, h = pin_len + 2, center = true);
                hull() {
                    translate([-(pin_len + 2)/2, -(pin_d - 0.4)/2, hinge_z0 - 3])
                        cube([pin_len + 2, pin_d - 0.4, 0.1]);
                    translate([-(pin_len + 2)/2, -(pin_d + 0.3)/2, pin_z - 1])
                        cube([pin_len + 2, pin_d + 0.3, 0.1]);
                }
                translate([-(pin_len + 2)/2, -(pin_d + 0.3)/2, pin_z - 1])
                    cube([pin_len + 2, pin_d + 0.3, 1]);
            }
        // snap grooves matching the base ridges
        for (sx = [-1, 1], sy = [-1, 1])
            translate([sx*in_w/2, sy*35, base_t - 1.6])
                rotate([90,0,0]) cylinder(r = snap_bump + 0.15, h = 15, center = true, $fn = 16);
        // USB-C charge opening in the bottom edge
        if (usb_hole)
            translate([esp_x, -out_h/2 + wall/2, base_t + 2 + 1.6])
                rotate([90,0,0]) hull()
                    for (sx = [-1, 1]) translate([sx*3.2, 0, 0])
                        cylinder(d = 4.2, h = wall + 2, center = true);
        // pry notch at the bottom edge to pop the shell off
        translate([0, -out_h/2, 0]) cube([12, 3, 2.4], center = true);
    }
}

/* ======================= ROCKER ======================= */
// Modelled in place (front face at z = depth).
module rocker() {
    // paddle, slightly crowned look via a chamfered front edge
    translate([0,0,rocker_back]) hull() {
        rrect(rocker_w, rocker_h, 2.5, rocker_t - 0.6);
        rrect(rocker_w - 1.2, rocker_h - 1.2, 1.9, rocker_t);
    }
    // hinge bar (wider than the opening, sits behind the front wall)
    translate([-hinge_reach, -3, hinge_z0]) cube([2*hinge_reach, 6, 3.01]);
    // pivot pins
    for (sx = [-1, 1])
        translate([sx*(hinge_reach + pin_len/2 - 0.01), 0, pin_z])
            rotate([0,90,0]) cylinder(d = pin_d, h = pin_len, center = true);
    // nubs that press the tactile switches
    for (sy = [-1, 1])
        translate([tact_x, sy*tact_y, switch_top + nub_gap])
            cylinder(d = 4, h = rocker_back - (switch_top + nub_gap) + 0.01);
    // small ribs so the top/bottom halves are easy to feel in the dark
    for (sy = [-1, 1])
        translate([0, sy*(rocker_h/2 - 8), depth - 0.01])
            rrect(14, 1.6, 0.7, 0.6);
}

/* ======================= dummy parts for the preview ======================= */
module dummy_toggle() {
    color("ivory") {
        translate([0,0,-10]) rrect(30, 85, 2, 10);              // switch body
        translate([0,0,0]) rotate([-15,0,0])
            hull() {
                cylinder(d = 7, h = 1);
                translate([0, 0, 14]) scale([1, 0.6, 1]) sphere(d = 6);
            }
    }
}
module dummy_electronics() {
    color("royalblue") translate([esp_x, esp_y, base_t + 2]) cube([17.5, 21, 1.6], center = true);
    color("silver")    translate([esp_x, esp_y - 9.5, base_t + 2 + 2.4]) cube([9, 7.5, 3.2], center = true);
    color("dimgray")   translate([batt_x, batt_y, base_t + 4]) cube([40, 30, 8], center = true);
    for (sy = [-1, 1]) {
        color("black") translate([tact_x, sy*tact_y, pillar_top - pocket_depth + 1.75]) cube([6, 6, 3.5], center = true);
        color("red")   translate([tact_x, sy*tact_y, pillar_top - pocket_depth + 3.5]) cylinder(d = 3.5, h = tact_h_total - 3.5);
    }
}

/* ======================= output ======================= */
if (part == "base") base();
else if (part == "shell") translate([0,0,depth]) rotate([180,0,0]) shell();      // front face down
else if (part == "rocker") translate([0,0,depth]) rotate([180,0,0]) rocker();    // paddle face down
else if (part == "cutaway") {
    difference() {
        union() {
            dummy_toggle();
            color("white") base();
            dummy_electronics();
            color("lightgray") shell();
            color("orange") rocker();
        }
        translate([-100, -100, -50]) cube([100 + tact_x, 200, 100]);
    }
}
else if (part == "assembled") {   // as it looks on the wall
    color("gainsboro") translate([0,0,-1]) cube([260, 260, 2], center = true);   // wall
    color("white") shell();
    color("white") rocker();
}
else {  // assembly, exploded
    dummy_toggle();
    color("white") base();
    dummy_electronics();
    color("lightgray", 0.55) translate([0,0,30]) shell();
    color("orange") translate([0,0,60]) rocker();
}
