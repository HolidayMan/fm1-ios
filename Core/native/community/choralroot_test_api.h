/* Test-only native source inspection. App artifacts never include this file. */
uint32_t chr_test_init_counts(void) { return ENG_CZ.npresets==1 && ENG_P5_TEST.npresets==1; }
uint32_t chr_test_sound(uint32_t engine) {
    if (engine>1) return 0;
    cu_load(trk,engine?ENGI_PROPHET:ENGI_CZ,0,0);
    return trk[0].eng_req==(engine?ENGI_PROPHET:ENGI_CZ);
}
uint32_t chr_test_user_store(uint32_t engine) {
    if (!chr_test_sound(engine)) return 0;
    if (!engine) ENGINES[ENGI_CZ]->deep->set(trk,0,0,5);
    else ENGINES[ENGI_PROPHET]->deep->set(trk,0,0,18);
    int result=up_store(engine?5:4,engine?"PRIVATE P5":"PRIVATE CZ");
    return result==0 || result==3;
}
uint32_t chr_test_user_load(uint32_t engine) {
    cu_load_user(trk,engine?5:4,0);
    return trk[0].eng_req==(engine?ENGI_PROPHET:ENGI_CZ);
}
uint32_t chr_test_user_bytes(uint32_t engine,uint8_t *out) {
    const eng_deep_t *d=ENGINES[engine?ENGI_PROPHET:ENGI_CZ]->deep;
    d->blob_get(trk,out);return d->blob_size;
}
