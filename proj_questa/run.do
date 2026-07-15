transcript on

if {[file exists work]} {
vdel -lib work -all
}

vlib work
vmap work work

# Compilación
vlog -sv ../src/*.sv

# Simulación
vsim -voptargs=+acc work.neural_network_digits_tb

# Corre toda la simulación
run -all