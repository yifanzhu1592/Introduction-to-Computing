; My solution is based on the approach used in examples "Undef Example - Writing a handler for Undefined Instruction Exceptions" and
; "Example: Timer using Interrupts" from the lecture material for CSU11022
;
; CS1022 Introduction to Computing II 2018/2019
; Chess Clock
;

T0IR		EQU	0xE0004000
T0TCR		EQU	0xE0004004
T0TC		EQU	0xE0004008
T0MR0		EQU	0xE0004018
T0MCR		EQU	0xE0004014

PINSEL4		EQU	0xE002C010

FIO2DIR1	EQU	0x3FFFC041
FIO2PIN1	EQU	0x3FFFC055

EXTINT		EQU	0xE01FC140
EXTMODE		EQU	0xE01FC148
EXTPOLAR	EQU	0xE01FC14C

VICIntSelect	EQU	0xFFFFF00C
VICIntEnable	EQU	0xFFFFF010
VICVectAddr0	EQU	0xFFFFF100
VICVectPri0	EQU	0xFFFFF200
VICVectAddr	EQU	0xFFFFFF00

VICVectT0	EQU	4
VICVectEINT0	EQU	14

Irq_Stack_Size	EQU	0x80

Mode_USR        EQU     0x10
Mode_IRQ        EQU     0x12
I_Bit           EQU     0x80            ; when I bit is set, IRQ is disabled
F_Bit           EQU     0x40            ; when F bit is set, FIQ is disabled



	AREA	RESET, CODE, READONLY
	ENTRY

	; Exception Vectors

	B	Reset_Handler	; 0x00000000
	B	Undef_Handler	; 0x00000004
	B	SWI_Handler	; 0x00000008
	B	PAbt_Handler	; 0x0000000C
	B	DAbt_Handler	; 0x00000010
	NOP			; 0x00000014
	B	IRQ_Handler	; 0x00000018
	B	FIQ_Handler	; 0x0000001C

;
; Reset Exception Handler
;
Reset_Handler

	;
	; Initialize Stack Pointers (SP) for each mode we are using
	;

	; Stack Top
	LDR	R0, =0x40010000

	; Enter irq mode and set initial SP
	MSR     CPSR_c, #Mode_IRQ:OR:I_Bit:OR:F_Bit
	MOV     SP, R0
	SUB     R0, R0, #Irq_Stack_Size

	; Enter user mode and set initial SP
	MSR     CPSR_c, #Mode_USR
	MOV	SP, R0

	;
	; your initialisation goes here
	;
	
	;
	; Configure P2.10 for EINT0
	;

	; Enable P2.10 for GPIO
	LDR	R4, =PINSEL4
	LDR	R5, [R4]		; read current value
	BIC	R5, #(0x03 << 20)	; clear bits 21:20
	ORR	R5, #(0x01 << 20)	; set bits 21:20 to 01
	STR	R5, [R4]		; write new value

	; Set edge-sensitive mode for EINT0
	LDR	R4, =EXTMODE
	LDR	R5, [R4]		; read
	ORR	R5, #1			; modify
	STRB	R5, [R4]		; write

	; Set rising-edge mode for EINT0
	LDR	R4, =EXTPOLAR
	LDR	R5, [R4]		; read
	BIC	R5, #1			; modify
	STRB	R5, [R4]		; write

	; Reset EINT0
	LDR	R4, =EXTINT
	MOV	R5, #1
	STRB	R5, [R4]

	;
	; Configure VIC for EINT0 interrupts
	;

	; Useful VIC vector numbers and masks for following code
	LDR	R4, =VICVectEINT0		; vector 14
	LDR	R5, =(1 << VICVectEINT0) 	; bit mask for vector 14

	; VICIntSelect - Clear bit 4 of VICIntSelect register to cause
	; channel 14 (EINT0) to raise IRQs (not FIQs)
	LDR	R6, =VICIntSelect	; addr = VICVectSelect;
	LDR	R7, [R6]		; tmp = Memory.Word(addr);
	BIC	R7, R7, R5		; Clear bit for Vector 14
	STR	R7, [R6]		; Memory.Word(addr) = tmp;

	; Set Priority for VIC channel 14 (EINT0) to lowest (15) by setting
	; VICVectPri4 to 15. Note: VICVectPri4 is the element at index 14 of an
	; array of 4-byte values that starts at VICVectPri0.
	; i.e. VICVectPri4=VICVectPri0+(4*4)
	LDR	R6, =VICVectPri0	; addr = VICVectPri0;
	MOV	R7, #15			; pri = 15;
	STR	R7, [R6, R4, LSL #2]	; Memory.Word(addr + vector * 4) = pri;

	; Set Handler routine address for VIC channel 4 (TIMER0) to address of
	; our handler routine (TimerHandler). Note: VICVectAddr4 is the element
	; at index 4 of an array of 4-byte values that starts at VICVectAddr0.
	; i.e. VICVectAddr4=VICVectAddr0+(4*4)
	LDR	R6, =VICVectAddr0	; addr = VICVectAddr0;
	LDR	R7, =Button_Handler	; handler = address of TimerHandler;
	STR	R7, [R6, R4, LSL #2]	; Memory.Word(addr + vector * 4) = handler

	; Enable VIC channel 14 (EINT0) by writing a 1 to bit 4 of VICIntEnable
	LDR	R6, =VICIntEnable	; addr = VICIntEnable;
	STR	R5, [R6]		; enable interrupts for vector 14
	
	;
	; Configure TIMER0
	;

	; Stop and reset TIMER0 using Timer Control Register
	; Set bit 0 of TCR to 0 to stop TIMER
	; Set bit 1 of TCR to 1 to reset TIMER
	LDR	R5, =T0TCR
	LDR	R6, =0x2
	STRB	R6, [R5]

	; Clear any previous TIMER0 interrupt by writing 0xFF to the TIMER0
	; Interrupt Register (T0IR)
	LDR	R5, =T0IR
	LDR	R6, =0xFF
	STRB	R6, [R5]
	
	; Start TIMER0 using the Timer Control Register
	; Set bit 0 of TCR (0xE0004004) to enable the timer
	LDR	R4, =T0TCR
	LDR	R5, =0x01
	STRB	R5, [R4]
	
	; Initialisation
	LDR	R4, =0x40000000		; the length of time the first player has spent
	MOV	R5, #0
	STR	R5, [R4]
	LDR	R4, =0x40000004		; the length of time the second player has spent
	MOV	R5, #0
	STR	R5, [R4]
	LDR	R4, =0x40000010		; the length of time the game has passed at the last time the button was pressed
	MOV	R5, #0
	STR	R5, [R4]
	LDR	R4, =0x40000030		; determines whose turn it is
	MOV	R5, #0
	STR	R5, [R4]

	; Continuously checking if one of the players has run out of time
	LDR	R6, =15000000
loop
	LDR	R4, =0x40000010
	LDR	R9, [R4]
	LDR	R4, =T0TC
	LDR	R5, [R4]
	SUB	R5, R5, R9

	LDR	R4, =0x40000030
	LDR	R7, [R4]
	CMP	R7, #0
	BNE	second
	LDR	R4, =0x40000000
	B	first
second
	LDR	R4, =0x40000004
first
	LDR	R7, [R4]
	ADD	R5, R5, R7
	CMP	R5, R6			; the value of R5 is the length of time the first player (if R7 == 0) or the second player (if R7 == 1) has spent
	BLO	loop
	STR	R5, [R4]
	
	; Stop TIMER0 using Timer Control Register
	; Set bit 0 of TCR to 0 to stop TIMER
	LDR	R5, =T0TCR
	LDR	R6, =0x0
	STRB	R6, [R5]
	
	; Disable P2.10 for GPIO
	LDR	R4, =PINSEL4
	LDR	R5, [R4]		; read current value
	BIC	R5, #(0x03 << 20)	; clear bits 21:20
	STR	R5, [R4]		; write new value

stop	B	stop


;
; TOP LEVEL EXCEPTION HANDLERS
;

;
; Software Interrupt Exception Handler
;
Undef_Handler
	B	Undef_Handler

;
; Software Interrupt Exception Handler
;
SWI_Handler
	B	SWI_Handler

;
; Prefetch Abort Exception Handler
;
PAbt_Handler
	B	PAbt_Handler

;
; Data Abort Exception Handler
;
DAbt_Handler
	B	DAbt_Handler

;
; Interrupt ReQuest (IRQ) Exception Handler (top level - all devices)
;
IRQ_Handler
	SUB	lr, lr, #4	; for IRQs, LR is always 4 more than the
				; real return address
	STMFD	sp!, {r0-r3,lr}	; save r0-r3 and lr

	LDR	r0, =VICVectAddr; address of VIC Vector Address memory-
				; mapped register

	MOV	lr, pc		; can’t use BL here because we are branching
	LDR	pc, [r0]	; to a different subroutine dependant on device
				; raising the IRQ - this is a manual BL !!

	LDMFD	sp!, {r0-r3, pc}^ ; restore r0-r3, lr and CPSR

;
; Fast Interrupt reQuest Exception Handler
;
FIQ_Handler
	B	FIQ_Handler


;
; write your interrupt handlers here
;

;
; EINT0 IRQ Handler (device-specific handler called by top-level IRQ_Handler)
;
Button_Handler

	STMFD	sp!, {r4-r8, lr}

	; Reset EINT0 interrupt by writing 1 to EXTINT register
	LDR	R4, =EXTINT
	MOV	R5, #1
	STRB	R5, [R4]

	; The period of time between this button-press time and last time
	LDR	R4, =T0TC
	LDR	R5, [R4]
	LDR	R4, =0x40000010
	LDR	R6, [R4]
	STR	R5, [R4]
	SUB	R5, R5, R6
	
	; Update the value stored at 0x40000000 or 0x40000004 ( which are the lengths of time each of the players has spent)
	LDR	R4, =0x40000030
	LDR	R7, [R4]
	CMP	R7, #0
	BEQ	firstCounter
	LDR	R4, =0x40000004
	LDR	R8, [R4]
	ADD	R8, R8, R5
	STR	R8, [R4]
	LDR	R4, =0x40000030
	MOV	R7, #0
	STR	R7, [R4]
	B	secondCounter
firstCounter
	LDR	R4, =0x40000000
	LDR	R8, [R4]
	ADD	R8, R8, R5
	STR	R8, [R4]
	LDR	R4, =0x40000030
	MOV	R7, #1
	STR	R7, [R4]
secondCounter

	;
	; Clear source of interrupt
	;
	LDR	R4, =VICVectAddr	; addr = VICVectAddr
	MOV	R5, #0			; tmp = 0;
	STR	R5, [R4]		; Memory.Word(addr) = tmp;

	LDMFD	sp!, {r4-r8, pc}


	AREA	TestData, DATA, READWRITE

	END
