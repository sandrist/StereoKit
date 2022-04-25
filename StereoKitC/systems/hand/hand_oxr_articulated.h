#pragma once

namespace sk {

bool hand_oxra_available      ();
void hand_oxra_init           ();
void hand_oxra_shutdown       ();
void hand_oxra_update_inactive();
void hand_oxra_update_frame   ();
void hand_oxra_update_poses   (bool update_visuals);
void hand_oxra_get_pose_at_time(hand_t* hand, int64_t time);

}