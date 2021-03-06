;***********************************************************************
;Programa para anviar datos y leer o escribir en memoria EEPROM 93C46
;envio por bit bang.
;Programa  integrado
;MCU atmega328p
;Programador: dasa
;
;***********************************************************************
#include "m328Pdef.inc"

.equ CS = 0  ;Chip selected
.equ DO = 2  ;Digital output
.equ DI = 3  ;Digital input
.equ SCK = 1 ;Relog SCK

.equ adress = 0x01 ;Lee en memoria
.equ READ = 0x03   ;Lee en memoria
.equ WRITE = 0x05  ;Escribe memoria
.equ EWEN = 0x19   ;Activa Write en memoria

;Declaracion de registros===============================================
.def int_m = r0
.def tmp = r16
.def tmp2 = r17
.def tmp3 = r18
.def dato = r19
.def adds = r23

;inicio de programa
.org 0x0000
rjmp inicio
;interrupcion de usart RX
.org 0x0024
rjmp uart_rx
;interrupcion de usart TX
.org 0x0028
rjmp uart_tx

;inicio=================================================================
inicio:
	ldi tmp,high(RAMEND)	;Declaracion del stack pointer
	out SPH,tmp
	ldi tmp,low(RAMEND)
	out SPL,tmp
;Pines de salida de datos DO, CS Y SCK
	ldi tmp,(1<<DDB0)|(1<<DDB1)|(1<<DDB2)|(1<<DDB3)|(1<<DDB5)
	out DDRB,tmp
	ldi tmp,(1<<DDC0)|(1<<DDC1)|(1<<DDC2)|(1<<DDC5)
	out DDRC,tmp
	ldi tmp,(1<<PORTC3)
	out portC,tmp
	clr tmp
	out portB,tmp		;limpio puerto
;inicio de uart=========================================================
uart_in:
	clr tmp
	sts UBRR0H,tmp		;Cargo en UBRR0H 0x00
	ldi tmp,0x67		;Cargo en UBRR0L 0x67 o 103 que en la tabla de
	;datos Baud Rate Setting a 16MHZ es el valor para 9600 baudios
	sts UBRR0L,tmp
	;Recepcion interrup, RX y TX enable
	ldi tmp,(1<<RXCIE0)|(1<<RXEN0)|(1<<TXEN0)
	sts UCSR0B,tmp
;Character Size 8bit
	ldi tmp,(1<<UCSZ01)|(1<<UCSZ00)
	sts UCSR0C,tmp
;Limpio registros
	clr tmp
	clr tmp2
	clr tmp3
	clr adds
	clr dato
	sei
;=======================================================================
	ldi r30, low(mensaje<<1)
	ldi r31, high(mensaje<<1)
	rcall TX_ms

mensaje:
.db "1 READ DAT ADD",0x0A,"2 ENABLE W",0x0A,"3 WRITE ADD",0x0A,"4 READ ALL",0x0A,"5 WRITE 128",0x0A,"6 READ ADD",0x0A,"7 WRITE UART",0x0A,0x00

loop:
	tst tmp2
	breq loop
	rjmp test

adres_m:
.db "ADDRES",0x0A,0x00
datos_m:
.db "DATOS",0x0A,0x00

test:
	cpi tmp2,0x31
	brne e_enwri
e_read:
	sbi portC,CS		;chip selected ON
	ldi tmp3,3			;Op code tiempo
	ldi tmp,READ		;Op code
	rcall out_bit
	ldi tmp,adress
	ldi tmp3,7			;Pulsos para direccion
	rcall out_bit
	clr tmp
	ldi tmp3,9			;Pulsos para leer
	rcall in_bit
	cbi portC,CS		;chip selected OFF
	clr tmp2

e_enwri:
	cpi tmp2,0x32
	brne e_write
	sbi portC,CS		;chip selected ON
	ldi tmp3,3
	ldi tmp,EWEN		;Write enable
	rcall out_bit
	ldi tmp3,9
	ldi tmp,0x03		;Write enable
	rcall out_bit
	clr tmp
	cbi portC,CS		;chip selected OFF
	clr tmp2

e_write:
	cpi tmp2,0x33
	brne read_all
	clr tmp2			;Limpio tmp2 para esperar datos
	ldi r30, low(datos_m<<1)
	ldi r31, high(datos_m<<1)
	rcall TX_ms
datos:
	tst tmp2
	breq datos
	mov dato,tmp2
	clr tmp2
	ldi r30, low(adres_m<<1)
	ldi r31, high(adres_m<<1)
	rcall TX_ms
addres:
	tst tmp2
	breq addres
	mov adds,tmp2
	rcall delay
	sbi portC,CS		;chip selected ON
	ldi tmp3,3
	ldi tmp,WRITE
	rcall out_bit
	mov tmp,adds
	ldi tmp3,7
	rcall out_bit
	mov tmp,dato
	ldi tmp3,9
	rcall out_bit
	cbi portC,CS		;chip selected OFF
	clr tmp2

read_all:				;lee datos de toda la memoria
	cpi tmp2,0x34
	brne write_all
	clr adds
	clr dato
	clr tmp2
read_all_1:
	sbi portC,5			;Esta en una funcion
	sbi portC,CS		;chip selected ON
	ldi tmp3,3			;Op code tiempo
	ldi tmp,READ		;Op code
	rcall out_bit
	mov tmp,adds		;muevo valor a tmp
	ldi tmp3,7			;Pulsos para direccion
	rcall out_bit
	ldi tmp3,8			;Pulsos para leer
	rcall in_bit
	cbi portC,CS		;chip selected OFF
	rcall delay
	inc adds
	cpi adds,128
	breq pc+2
	rjmp read_all_1

write_all:				;Funcion para escribir de 0-128 HEX
	cpi tmp2,0x35
	brne read_uart
	ldi dato,128
	ldi adds,0x00
write_all_1:
	sbi portC,5			;Esta en una funcion
	sbi portC,CS		;chip selected ON
	ldi tmp3,3			;Op code tiempo
	ldi tmp,WRITE		;Op code
	rcall out_bit
	mov tmp,adds
	ldi tmp3,7			;Pulsos para direccion
	rcall out_bit
	mov tmp,dato
	ldi tmp3,9			;Pulsos para escribir
	rcall out_bit
	cbi portC,CS		;chip selected OFF
	rcall delay
	dec dato
	inc adds
	cpi dato,128
	breq exit
	rjmp write_all_1

read_uart:				;Lee datos de direccion especificada por UART
	cpi tmp2,0x36
	brne write_uart
	ldi r30, low(adres_m<<1)
	ldi r31, high(adres_m<<1)
	rcall TX_ms
	sbi portC,5
	clr adds
	clr dato
	clr tmp2
addres1:
	tst tmp2
	breq addres1
	mov adds,tmp2
	sbi portC,CS		;chip selected ON
	ldi tmp3,3
	ldi tmp,READ
	rcall out_bit
	mov tmp,adds
	ldi tmp3,7
	rcall out_bit
	ldi tmp3,8
	rcall in_bit
	cbi portC,CS		;chip selected OFF
	clr tmp2

write_uart:
	cpi tmp2,0x37
	brne exit
	sbi portC,5			;Esta en una funcion
	clr adds
	clr dato
	clr tmp2
whait_uart:
	tst tmp2
	breq whait_uart
	mov r5,tmp2
	cpi tmp2,'q'
	breq exit
	sbi portC,CS		;chip selected ON
	ldi tmp3,3			;Op code tiempo
	ldi tmp,WRITE		;Op code
	rcall out_bit
	mov tmp,adds		;muevo dato de uart a tmp2
	ldi tmp3,7			;Pulsos para direccion
	rcall out_bit
	ldi tmp3,9
	mov tmp,r5
	rcall out_bit
	clr tmp2
	inc adds
	cbi portC,CS
	rcall delay
	rjmp whait_uart

exit:
	clr tmp2
	cbi portC,5
	rjmp loop
;Lee datos de memoria===================================================
in_bit:
	sbi portC,SCK		;Pulso de relog sck
	rcall delay
	sbic pinC,3			;Checa si hay alto en pinC,3
	sec					;Carry = 1
	ror dato			;Roto a la izquierda dato 00000001<<
	cbi portC,SCK		;Pulso de relgo off
	rcall delay
	dec tmp3
	tst tmp3			;si es igual a 0
	brne in_bit
	mov tmp2,dato
	rcall uart_tx
	clr dato
	clc
	ret
;Salida de datos e instrucciones========================================
out_bit:
	;mov tmp2,tmp		;copio valor
	ror tmp				;Desplazo bite a la derecha
	brcc pc+2			;Si Carry bit es 0 salto sig instruccion
	sbi portC,DO		;Pulso de dato 1
	sbi portC,SCK		;Pulso de relog sck
	rcall delay
	cbi portC,DO		;Pulso de dato 0
	cbi portC,SCK		;Pulso de relgo off
	rcall delay
	dec tmp3			;decremento valor tmp3
	tst tmp3			;si es igual a 0
	brne out_bit
	clc
	ret

;Delays=================================================================
delay:
	in int_m,SREG		;Guardo status register
	
	ldi  r21, 20
	ldi  r22, 20
L1: dec  r22
	brne L1
	dec  r21
	brne L1
	out SREG,int_m
	ret

delay1:
	in int_m,SREG		;Guardo status register
	ldi  r20, 20
	ldi  r21, 10
	ldi  r22, 10
L2: dec  r22
	brne L2
	dec  r21
	brne L2
	dec  r20
	brne L2
	out SREG,int_m
	ret
;Interrupcion de UART TX================================================
uart_tx:
	in int_m,SREG		;Guardo status register
	lds tmp,UCSR0A		;almaceno en tmp UCSR0A
	sbrs tmp,UDRE0		;Salto siguiente instruccion si bit RXC0 es =1
	rjmp uart_tx
	sts UDR0,tmp2		;Envio dato a terminal TX
	out SREG,int_m
	ret
;Sub rutina de carga de datos===========================================
TX_ms:
	lpm tmp2,Z+			;Cargo de memoria de programa
	tst tmp2			;Checa si es = 0
	breq TX_fin			;si es igual a cero salta a TX_fin
	rcall uart_tx		;Salta para transmitir
	rjmp TX_ms			;bucle mientras sigue cargando datos
TX_fin:					;Termina transmision y regresa a lina de prog
	clr tmp2
	ret
;Interrupcion de UART===================================================
uart_rx:
	in int_m,SREG		;Guardo status register
	push tmp
	lds tmp,UDR0		;Carga en tmp dato recivido
	mov tmp2,tmp		;muevo tmp a tmp2 para comparar
	pop tmp
	out SREG,int_m
	reti


