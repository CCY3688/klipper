// Hardware USART2 support for EMM/ZDT stepper drivers on STM32F407 PA2/PA3.
//
// Install as ~/klipper/src/stm32/emm_usart.c and add
// "src-$(CONFIG_MACH_STM32F4) += stm32/emm_usart.c" to src/stm32/Makefile.

#include "autoconf.h" // CONFIG_MACH_STM32F4
#include "basecmd.h" // oid_alloc
#include "board/misc.h" // timer_from_us
#include "command.h" // DECL_COMMAND
#include "internal.h" // enable_pclock
#include "sched.h" // shutdown

#if CONFIG_MACH_STM32F4

#define EMM_USART USART2
#define EMM_GPIO_RX GPIO('A', 3)
#define EMM_GPIO_TX GPIO('A', 2)
#define EMM_RESPONSE_MAX 64

struct emm_usart_s {
    uint32_t baud, timeout_us;
};

static void
emm_usart_setup(uint32_t baud)
{
    if (!baud)
        shutdown("emm_usart: invalid baud");

    enable_pclock((uint32_t)EMM_USART);
    uint32_t pclk = get_pclock_frequency((uint32_t)EMM_USART);
    uint32_t div = DIV_ROUND_CLOSEST(pclk, baud);
    EMM_USART->CR1 = 0;
    EMM_USART->BRR = (((div / 16) << USART_BRR_DIV_Mantissa_Pos)
                      | ((div % 16) << USART_BRR_DIV_Fraction_Pos));
    EMM_USART->CR2 = 0;
    EMM_USART->CR3 = 0;
    EMM_USART->CR1 = USART_CR1_UE | USART_CR1_RE | USART_CR1_TE;

    gpio_peripheral(EMM_GPIO_RX, GPIO_FUNCTION(7), 1);
    gpio_peripheral(EMM_GPIO_TX, GPIO_FUNCTION(7), 0);
}

void
command_config_emm_usart(uint32_t *args)
{
    struct emm_usart_s *e = oid_alloc(args[0], command_config_emm_usart
                                      , sizeof(*e));
    e->baud = args[1];
    e->timeout_us = args[2];
    emm_usart_setup(e->baud);
}
DECL_COMMAND(command_config_emm_usart,
             "config_emm_usart oid=%c baud=%u timeout_us=%u");

static uint_fast8_t
emm_wait_sr(uint32_t mask, uint32_t timeout_us)
{
    uint32_t end = timer_read_time() + timer_from_us(timeout_us);
    for (;;) {
        if (EMM_USART->SR & mask)
            return 1;
        if (!timer_is_before(timer_read_time(), end))
            return 0;
    }
}

void
command_emm_usart_transfer(uint32_t *args)
{
    uint8_t oid = args[0];
    struct emm_usart_s *e = oid_lookup(oid, command_config_emm_usart);
    uint8_t write_len = args[1];
    uint8_t *write = command_decode_ptr(args[2]);
    uint8_t read_len = args[3];
    uint32_t timeout_us = args[4] ? args[4] : e->timeout_us;
    if (read_len > EMM_RESPONSE_MAX)
        shutdown("emm_usart: read too large");

    while (EMM_USART->SR & (USART_SR_RXNE | USART_SR_ORE))
        (void)EMM_USART->DR;

    for (uint8_t i = 0; i < write_len; i++) {
        if (!emm_wait_sr(USART_SR_TXE, timeout_us))
            shutdown("emm_usart: tx timeout");
        EMM_USART->DR = write[i];
    }
    if (!emm_wait_sr(USART_SR_TC, timeout_us))
        shutdown("emm_usart: tx complete timeout");

    uint8_t read[EMM_RESPONSE_MAX], count = 0;
    for (; count < read_len; count++) {
        if (!emm_wait_sr(USART_SR_RXNE | USART_SR_ORE, timeout_us))
            break;
        uint32_t sr = EMM_USART->SR, dr = EMM_USART->DR;
        if (sr & USART_SR_RXNE)
            read[count] = dr;
        else
            break;
    }
    sendf("emm_usart_response oid=%c response=%*s", oid, count, read);
}
DECL_COMMAND(command_emm_usart_transfer,
             "emm_usart_transfer oid=%c write=%*s read_len=%c timeout_us=%u");

#endif
