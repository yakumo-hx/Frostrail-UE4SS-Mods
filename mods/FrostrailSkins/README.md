# 人物皮肤 / Character Skins

在背包里试穿人物皮肤，给自己的角色换装，也可以换回原版。本包带换装功能和七款人物，更多人物在扩展包里，装上后出现在同一个菜单。

需要 UE4SS-FrostrailCore。进入战役默认穿水无ひより。打开背包，点人物预览旁的「人物皮肤」，点一个名字试穿，按「确定」应用。选「原版」并确定，换回游戏自带的人物。

## 本包的人物

水无ひより、千駄ヶ谷篠、英賀保芽依、Anime Female Mage、Anime Maid、Vita、朱迪。

## 扩展包

扩展包都要先装本包，想要哪几款就装哪个。

| 包 | 人物 |
| --- | --- |
| 人物皮肤 · 扩展一 `FrostrailSkinsPack1` | Celeste、Twf 2.0、Vfg 1.0、Laverisse、Eld 1.0 |
| 人物皮肤 · 扩展二 `FrostrailSkinsPack2` | Ao、AKUMAKO · 万圣节、波覇ありす、SuccubuS、女骑士、kiyria、Ayame Remi · 魔女、エプシロン・ノート、小倉小町、八咫みるく、姫廻ヒメ、羽霞 Waka、めるは |
| 人物皮肤 · 同人 `FrostrailSkinsFan` | Meltical · 魔女、黄色奶蛙 |

从 0.2.0 用管理器更新，已选人物和各款背部装备开关会保留。卸掉扩展包时，如果正穿着其中的人物，下次进游戏会换回原版。

## 说明

- 原版的头部、上衣和下装装备看不到，但仍穿在身上。手持物照常显示，第一人称的手和袖子也换成所选人物。
- 背包预览通常把手持物放在人物身侧，姫廻ヒメ的武器放在背后。
- 背部装备默认隐藏，每款可以在皮肤界面里单独开关，马上生效。这个开关只管游戏里的背部装备，人物模型自带的背包、飘带等饰物一直显示。
- 选择和背部开关保存在本包的 `config.json`，扩展包的人物也存在这里。
- 蹲下或抬腿时，部分人物的裙摆会随大腿抬起，个别角度能看到穿插。

**多人：** 只改你自己屏幕上的样子。别的玩家看到你是原版人物，你看到的别人也是原版。想换装的人自己装就行，房主不用装。

Mod 自有代码由 Yuuka 以 MIT 许可发布。模型和贴图沿用各自的许可，见下文。

## English

Try on character skins in your inventory and apply one to your character, or switch back to the original. This package has the skin menu and seven characters. Add-on packages add more characters to the same menu.

Requires UE4SS-FrostrailCore. Your character starts as Mizunashi Hiyori. Open the inventory and choose **Skins** beside the character preview. Select a name to try it on, then confirm. Select **Original** and confirm to restore the game's appearance.

Characters in this package: Mizunashi Hiyori, Sendagaya Shino, Agaho Mei, Anime Female Mage, Anime Maid, Vita and Judy.

| Add-on | Characters |
| --- | --- |
| Character Skins · Pack 1 `FrostrailSkinsPack1` | Celeste, Twf 2.0, Vfg 1.0, Laverisse, Eld 1.0 |
| Character Skins · Pack 2 `FrostrailSkinsPack2` | Ao, AKUMAKO · Halloween, 波覇ありす, SuccubuS, Female Knight, kiyria, Ayame Remi · Witch, EpsilonNought, Ogura Komachi, Yata Miruku, Himeme Hime, Waka, Meruha |
| Character Skins · Fan Works `FrostrailSkinsFan` | Meltical · Witch, Yellow Milk Frog |

Updating from 0.2.0 with the manager keeps your selected character and per-skin back equipment settings. Each add-on needs this package. If you remove an add-on while wearing one of its characters, you return to the original appearance next time.

- Head, top and bottom equipment is hidden but still worn. Held items stay visible, and the first-person hands and sleeves match the skin.
- The inventory preview usually shows held items at the character's side. Himeme Hime carries the weapon behind her.
- Back equipment is hidden by default. Each skin has its own toggle on the Skins page, and it takes effect immediately. Backpacks and accessories that belong to the model always show.
- Some skirts lift with the thighs when crouching, and clipping can show from some angles.
- In multiplayer only your own screen changes. Other players see your original character, and you see theirs. Only players who want a skin need this package; the host does not.

## 模型来源和许可 / Model credits

- 水无ひより（Mizunashi Hiyori）：取自 ひみこ／HENGE《水無ひより》的 CC0 FBX 与 CC0 Texture。使用 ClimbWear 造型，重新蒙皮并制作游戏用贴图。[模型出处](https://booth.pm/en/items/6120660)
- 千駄ヶ谷篠（Sendagaya Shino）：pixiv 的 VRoid Studio β 版示例角色，CC0。[角色与许可](https://vroid.pixiv.help/hc/en-us/articles/360013482714)
- Vita：pixiv 的 VRoid Studio β 版 AvatarSample_3，CC0。[角色与许可](https://vroid.pixiv.help/hc/en-us/articles/360014900113)
- Anime Female Mage：Dawn to Dusk Games 的免费 Tier 1 人物和贴图，CC0。[作者原档与许可](https://dawn-to-dusk-games.itch.io/3d-anime-female-mage-character)
- Anime Maid：413 Games，CC0。原包附 License.txt。[作者原档](https://413games.itch.io/maid-character) · [作者许可说明](https://413games.itch.io/maid-character/devlog/412198/added-licence-file) · [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)
- 朱迪（Judy）：来自 David Glynch 的《bikini girl》。本包精简了模型细节，重绑到游戏骨架，调整泳装与身体的蒙皮，制作了第一人称网格并合并贴图。模型及其改编使用 CC BY 4.0。[原模型](https://sketchfab.com/3d-models/bikini-girl-f7cc8de297bc4e90aaf09434c3ad7f10) · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)

英賀保芽依（Agaho Mei），制服版 V1.0，使用 CC BY 4.0。作者署名如下。

> 「こうしす！キャラクター3Dモデル」
>
> ©京姫鉄道合同会社.
>
> モデル制作: 佐久間蒼乃
>
> 原作: 「こうしす！」©OPAP-JP contributors (https://opap.jp/contributors).

原模型改编自《こうしす！》的角色设计。本包将制服版重新蒙皮到游戏骨架，调整发梢、袖口和裙摆权重，制作第一人称手袖与身腿，将原贴图合为底色图集。该模型及其改编使用 CC BY 4.0。[V1.0 模型来源](https://github.com/kyoki-railway/kosys-character-3d/blob/8373701d649c3bf9caccf8f6ef0e75d676bb92e5/agaho-mei-uniform.vrm) · [作者许可与署名](https://github.com/kyoki-railway/kosys-character-3d/blob/8373701d649c3bf9caccf8f6ef0e75d676bb92e5/LICENSE.md) · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
