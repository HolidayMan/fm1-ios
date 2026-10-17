/* Isolated QA fixture, included only by a local test/generator wrapper after sloop_core.c.
 * Requires a freshly initialized, bound instance with a NEW synthetic flash image.
 * Never call on an owner's live instrument. Uses the pinned firmware's own defaults,
 * parameter clamps, step encodings, lock writer, capture and persistence functions.
 * This is a demanding valid mixed workload, not a proof of the global slowest patch.
 */
static int fm1_stress_fixture_prepare(uint32_t variant)
{
    static const uint32_t layouts[3][NPART] = {
        {ENGI_FM6, ENGI_PHYS, ENGI_GRAIN},
        {ENGI_FM6, ENGI_FM6, ENGI_FM6},
        {ENGI_FM6, ENGI_NOISE, ENGI_GRAIN}
    };
    if (variant >= NELEM(layouts)) return -1;
    const uint32_t *engines = layouts[variant];
    static const uint8_t counts[NPART] = {4, 2, 2}; /* eight shared synth voices */
    static const uint8_t notes[NPART][4] = {{48, 55, 60, 64}, {45, 57, 0, 0}, {60, 67, 0, 0}};
    uint32_t p, s, k;
    seq_stop();
    song.rec = 0;
    song.solo = 0;
    song.sel = TRK_DRUM;
    FEL(global_set)(G_BPM, 240);
    FEL(global_set)(G_CLOCK, 0);
    FEL(global_set)(G_SYNC, 0);
    FEL(global_set)(G_DFDBK, 120);
    FEL(global_set)(G_DCOLOR, 96);
    FEL(global_set)(G_DMIX, 127);
    FEL(global_set)(G_RSIZE, 127);
    FEL(global_set)(G_RDAMP, 32);
    FEL(global_set)(G_CRATE, 100);
    FEL(global_set)(G_CDEPTH, 127);
    FEL(global_set)(G_DRREV, 127);
    FEL(global_set)(G_DRDLY, 127);
    FEL(global_set)(G_DUST, 72);
    FEL(global_set)(G_DUCK, 40);
    FEL(global_set)(G_FILT, -18);
    FEL(global_set)(G_TXSRC, 3); /* built-in RAIN, no external sample dependency */
    FEL(global_set)(G_TXLVL, 100);
    FEL(global_set)(G_TXTONE, -16);
    FEL(global_set)(G_TXMOVE, 127);
    FEL(global_set)(G_TXRATE, 0);
    FEL(global_set)(G_TXWHEN, 0);
    FEL(global_set)(G_TXDUCK, 1);
    for (p = 0; p < NTRK; ++p) {
        track_t *t = &trk[p];
        track_defaults_steps(t);
        if (p < NPART) {
            FEL(set_engine)(p, engines[p]);
            FEL(apply_preset)(p, 0);
            /* Fresh fixture: no old sounding engine to fade out. */
            t->engine = t->eng_req;
        }
        FEL(param_set)(p, P_LEVEL, 80);
        FEL(param_set)(p, P_MUTE, 0);
        FEL(param_set)(p, P_SLEN, NSTEP);
        FEL(param_set)(p, P_SDIV, 3); /* user-visible 1/32, fastest step division */
        FEL(param_set)(p, P_SGATE, 127);
        FEL(param_set)(p, P_SSWING, 0);
        FEL(param_set)(p, P_DIST, 96);
        FEL(param_set)(p, P_CHOR, 127);
        FEL(param_set)(p, P_DLY, 127);
        FEL(param_set)(p, P_REV, 127);
        FEL(param_set)(p, P_TFLT, -24);
        FEL(param_set)(p, P_ITYPE, p == 0 ? 6 : p == 1 ? 7 : 8); /* phaser/flanger/chorus */
        FEL(param_set)(p, P_IA, 96);
        FEL(param_set)(p, P_IB, 120);
        FEL(param_set)(p, P_IC, 110);
        FEL(param_set)(p, P_IMIX, 96);
        FEL(param_set)(p, P_SLCR, SL_STUT);
        FEL(param_set)(p, P_SLPAT, 16);
        FEL(param_set)(p, P_SLRATE, 3);
        FEL(param_set)(p, P_SLDEPTH, 80);
        if (p < NPART) {
            FEL(param_set)(p, P_VOICE, V_POLY);
            FEL(param_set)(p, P_ATK, 0);
            FEL(param_set)(p, P_SUS, 127);
            FEL(param_set)(p, P_REL, 127);
            FEL(param_set)(p, P_AMODE, 0); /* dense sequencer chords, not an arp replacing them */
            FEL(param_set)(p, P_LRATE, 110);
            FEL(param_set)(p, P_LD_FLT, 48);
            FEL(param_set)(p, P_LD_SHP, 48);
        }
        for (s = 0; s < NSTEP; ++s) {
            if (p < NPART) {
                step_t *st = &t->step[s];
                st->n = counts[p];
                st->time = ST_NOTE;
                st->vel = 110;
                for (k = 0; k < counts[p]; ++k) {
                    st->note[k] = notes[p][k] + ((s / 8u) & 1u ? 2u : 0u);
                    st->lvl |= (uint8_t)(LV_HARD << (2u * k));
                    st->rat |= (uint8_t)(3u << (2u * k)); /* x4 */
                }
            } else {
                for (k = 0; k < DRUM_LANES; ++k)
                    dstep_set(&t->dstep[s], k, LV_HARD, 3u);
            }
            t->micro[s] = (int8_t)(s & 1u ? 3 : -3);
        }
        t->seq_active = 1;
        for (k = 0; k < NLOCK; ++k)
            if (!lock_set(t, k * 2u, P_TFLT, k & 1u ? 24 : -32)) return -2;
    }
    if (engines[1] == ENGI_PHYS) {
    FEL(param_set)(1, P_E0, PM_SYMP); /* two valid sympathetic-string voices */
    FEL(param_set)(1, P_E1, 100);
    FEL(param_set)(1, P_E2, 110);
    FEL(param_set)(1, P_E3, 40);
    FEL(param_set)(1, P_E6, 110);
    }
    if (engines[2] == ENGI_GRAIN) {
    FEL(param_set)(2, P_E2, 127); /* long grains */
    FEL(param_set)(2, P_E3, 127); /* highest legal grain density, pool still capped at 12 */
    FEL(param_set)(2, P_E5, 100);
    FEL(param_set)(2, P_E6, 100);
    }
    FEL(param_set)(3, P_E0, DRUM_DEFAULT_KIT); /* synthesized 808 */
    for (k = 0; k < 4u; ++k) section_store(k);
    persist_flush_now();
    /* Stay stopped: the physical PLAY action must start the measured run. */
    return song.playing || song.solo || song.rec ? -3 : 0;
}

/* Local QA instrumentation only. Counts actual active work, not allocated capacity.
 * Fields: playing, active synth voices by part (3), active drums, live grains,
 * populated steps by track (4), mute mask, solo mask, BPM.
 */
static uint32_t fm1_stress_fixture_observe(uint32_t *out, uint32_t capacity)
{
    uint32_t v[13] = {0}, p, k;
    v[0] = song.playing;
    for (p = 0; p < NPART; ++p)
        for (k = 0; k < NVOICE; ++k)
            v[1u + p] += trk[p].v[k].active && trk[p].v[k].stage != 4u;
    for (k = 0; k < NDRUM; ++k) v[4] += drums.v[k].active != 0;
    if (eng_arena_own[2] == ENGI_GRAIN + 1u) {
        const gr_part_t *g = (const gr_part_t *)&eng_arena[2];
        for (k = 0; k < GR_NG; ++k) v[5] += g->g[k].owner && g->g[k].left;
    }
    for (p = 0; p < NTRK; ++p) {
        for (k = 0; k < NSTEP; ++k)
            v[6u + p] += p == TRK_DRUM ? dstep_mask(&trk[p].dstep[k]) != 0 : trk[p].step[k].n != 0;
        if (trk[p].p[P_MUTE]) v[10] |= 1u << p;
    }
    v[11] = song.solo;
    v[12] = (uint32_t)song.g[G_BPM];
    if (capacity > NELEM(v)) capacity = NELEM(v);
    for (k = 0; k < capacity; ++k) out[k] = v[k];
    return capacity;
}
