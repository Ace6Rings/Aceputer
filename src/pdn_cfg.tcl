source $::env(SCRIPTS_DIR)/openroad/common/pdn_cfg.tcl

define_pdn_grid \
    -macro \
    -instances sram_inst \
    -name sram_macro_grid \
    -starts_with POWER \
    -halo "1.0 1.0"

add_pdn_connect \
    -grid sram_macro_grid \
    -layers "Metal4 Metal3"
