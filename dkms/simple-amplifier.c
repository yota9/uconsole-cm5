// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2017 BayLibre, SAS.
 * Author: Jerome Brunet <jbrunet@baylibre.com>
 *
 * ---------------------------------------------------------------------------
 * uConsole CM5 modification: auto-mute speakers on headphone insertion.
 * Base is verbatim mainline sound/soc/codecs/simple-amplifier.c
 * Added: optional 'hp-det' GPIO. On change, force the amplifier enable-GPIO low
 * (headphones in) or hand control back to DAPM (headphones out).
 * Hardware [uConsole V3.14-V5]: enable = PA_EN = RP1 GPIO11 (active-high,
 * 1 = speakers on); hp-det = HP_DET = RP1 GPIO10 (high = headphones inserted).
 * ---------------------------------------------------------------------------
 */

#include <linux/gpio/consumer.h>
#include <linux/module.h>
#include <linux/interrupt.h>
#include <linux/regulator/consumer.h>
#include <sound/soc.h>

#define DRV_NAME "simple-amplifier"

struct simple_amp {
	struct gpio_desc *gpiod_enable;
	struct gpio_desc *gpiod_hp_det;
	int hp_irq;
	bool dapm_on;
};

static void simple_amp_update(struct simple_amp *priv)
{
	int hp = 0;

	if (priv->gpiod_hp_det)
		hp = gpiod_get_value_cansleep(priv->gpiod_hp_det); /* 1 = headphones inserted */

	/* speakers on only if stream is playing AND no headphones */
	gpiod_set_value_cansleep(priv->gpiod_enable, (priv->dapm_on && !hp) ? 1 : 0);
}

static irqreturn_t simple_amp_hp_irq(int irq, void *data)
{
	struct simple_amp *priv = data;

	simple_amp_update(priv);
	return IRQ_HANDLED;
}

static int drv_event(struct snd_soc_dapm_widget *w,
		     struct snd_kcontrol *control, int event)
{
	struct snd_soc_component *c = snd_soc_dapm_to_component(w->dapm);
	struct simple_amp *priv = snd_soc_component_get_drvdata(c);

	switch (event) {
	case SND_SOC_DAPM_POST_PMU:
		priv->dapm_on = true;
		break;
	case SND_SOC_DAPM_PRE_PMD:
		priv->dapm_on = false;
		break;
	default:
		WARN(1, "Unexpected event");
		return -EINVAL;
	}

	simple_amp_update(priv);

	return 0;
}

static const struct snd_soc_dapm_widget simple_amp_dapm_widgets[] = {
	SND_SOC_DAPM_INPUT("INL"),
	SND_SOC_DAPM_INPUT("INR"),
	SND_SOC_DAPM_OUT_DRV_E("DRV", SND_SOC_NOPM, 0, 0, NULL, 0, drv_event,
			       (SND_SOC_DAPM_POST_PMU | SND_SOC_DAPM_PRE_PMD)),
	SND_SOC_DAPM_OUTPUT("OUTL"),
	SND_SOC_DAPM_OUTPUT("OUTR"),
	SND_SOC_DAPM_REGULATOR_SUPPLY("VCC", 20, 0),
};

static const struct snd_soc_dapm_route simple_amp_dapm_routes[] = {
	{ "DRV", NULL, "INL" },
	{ "DRV", NULL, "INR" },
	{ "OUTL", NULL, "VCC" },
	{ "OUTR", NULL, "VCC" },
	{ "OUTL", NULL, "DRV" },
	{ "OUTR", NULL, "DRV" },
};

static const struct snd_soc_component_driver simple_amp_component_driver = {
	.dapm_widgets		= simple_amp_dapm_widgets,
	.num_dapm_widgets	= ARRAY_SIZE(simple_amp_dapm_widgets),
	.dapm_routes		= simple_amp_dapm_routes,
	.num_dapm_routes	= ARRAY_SIZE(simple_amp_dapm_routes),
};

static int simple_amp_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct simple_amp *priv;
	int ret;

	priv = devm_kzalloc(dev, sizeof(*priv), GFP_KERNEL);
	if (priv == NULL)
		return -ENOMEM;
	platform_set_drvdata(pdev, priv);

	priv->gpiod_enable = devm_gpiod_get_optional(dev, "enable",
						     GPIOD_OUT_LOW);
	if (IS_ERR(priv->gpiod_enable))
		return dev_err_probe(dev, PTR_ERR(priv->gpiod_enable),
				     "Failed to get 'enable' gpio");

	priv->gpiod_hp_det = devm_gpiod_get_optional(dev, "hp-det", GPIOD_IN);
	if (IS_ERR(priv->gpiod_hp_det))
		return dev_err_probe(dev, PTR_ERR(priv->gpiod_hp_det),
				     "Failed to get 'hp-det' gpio");

	if (priv->gpiod_hp_det) {
		/* debounce */
		gpiod_set_debounce(priv->gpiod_hp_det, 150 * 1000);

		priv->hp_irq = gpiod_to_irq(priv->gpiod_hp_det);
		if (priv->hp_irq > 0) {
			ret = devm_request_threaded_irq(dev, priv->hp_irq,
					NULL, simple_amp_hp_irq,
					IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING |
					IRQF_ONESHOT,
					"simple-amp-hp-det", priv);
			if (ret)
				dev_warn(dev, "hp-det irq request failed: %d\n", ret);
		}
		/* initial state (headphones may be plugged at boot) */
		simple_amp_update(priv);
	}

	return devm_snd_soc_register_component(dev,
					       &simple_amp_component_driver,
					       NULL, 0);
}

#ifdef CONFIG_OF
static const struct of_device_id simple_amp_ids[] = {
	{ .compatible = "dioo,dio2125", },
	{ .compatible = "simple-audio-amplifier", },
	{ }
};
MODULE_DEVICE_TABLE(of, simple_amp_ids);
#endif

static struct platform_driver simple_amp_driver = {
	.driver = {
		.name = DRV_NAME,
		.of_match_table = of_match_ptr(simple_amp_ids),
	},
	.probe = simple_amp_probe,
};

module_platform_driver(simple_amp_driver);

MODULE_DESCRIPTION("ASoC Simple Audio Amplifier driver (uConsole CM5 hp-det variant)");
MODULE_AUTHOR("Jerome Brunet <jbrunet@baylibre.com>");
MODULE_LICENSE("GPL");
