/* SPDX-License-Identifier: GPL-3.0-only
 * Direct actual-source SONG REST regression, no production adapter hooks.
 * First run skiff_build.py with --out Research/NativeSkiff14/host-build.
 * Copy this file to that output's native/, then compile there with:
 * clang -O2 -w -DFELUCCA_VERSION='"v1.4"' -I../../upstream-skiff/build/gen skiff14_song.c -lm -o ../song-test
 */
#define main skiff_unused_host_main
#include "skiff_core.c"
#undef main
#include <assert.h>
int main(void) {
 memset(nor,255,sizeof nor);skf_init();
 /* Start with the upstream synthetic musical workload, actual tracks/patterns. */
 web_test_heavy();transport_stop_now();bank_poll();
 /* Put a real pattern on A and an explicit REST on B, track 2 remains musical. */
 assert(trk_keep(0)==0);assert(trk_pid[0]);
 assert(song_put(0,0,trk_pid[0])==0);
 unsigned pattern=lists.ent[0][0][0];assert(pattern&&pattern!=PAT_REST);
 assert(song_put(0,1,PAT_REST)==0);assert(ent_rest(0,1));
 assert(ent_go(0,0)==0);assert(!seq_is_empty(&trk[0]));
 unsigned other_empty=seq_is_empty(&trk[1]);assert(!other_empty);
 assert(ent_go(0,1)==0);assert(seq_is_empty(&trk[0]));assert(!seq_is_empty(&trk[1]));assert(trk_pid[0]==0);
 /* Render real ISR/DSP while resting: the independent track advances. */
 lists.song=0;seq_start();unsigned previous=trk[1].seq_idx,advanced=0;int32_t pcm[256];
 for(unsigned n=0;n<400;n++){skf_render(pcm,128);advanced|=trk[1].seq_idx!=previous;}
 assert(advanced);assert(seq_is_empty(&trk[0]));transport_stop_now();
 /* The actual list scheduler must queue the original source again after REST. */
 lists.song=1;song.playing=1;song_poll();assert(launch_q[0].armed);assert(launch_q[0].slot==0);assert(launch_q[0].id==pattern-1);song.playing=0;launch_q[0].armed=0;
 assert(ent_go(0,0)==0);assert(!seq_is_empty(&trk[0]));assert(!seq_is_empty(&trk[1]));
 assert(project_save(3)==0);lists.ent[0][1][0]=0;project_load(3);assert(lists.ent[0][1][0]==PAT_REST);
 puts("{\"source\":\"Skiff1.4\",\"songRestSilencesTrackSteps\":true,\"otherTrackContinues\":true,\"schedulerReturnsToPattern\":true,\"sourceReloads\":true,\"restProjectPersistence\":true}");
}
