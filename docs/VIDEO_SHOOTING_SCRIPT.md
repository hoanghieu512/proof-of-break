# Kịch bản quay — demo 3 phút

Tài liệu nội bộ, đi kèm `VIDEO_OUTLINE_demo-3min.md`. Outline nói **quay gì**;
cái này nói **bấm gì, chờ bao lâu, nói câu nào ở giây nào**.

---

## Quyết định lớn: quay 5 đoạn rời, không quay một mạch

**Cắt giữa các khối được. Cắt trong khối demo thì không.**

| | |
|---|---|
| Khối 1, 2, 4, 5 | Nói đè lên hình tĩnh. Vấp thì quay lại, **không tốn gì**. |
| **Khối 3 (demo)** | **Một take liền mạch.** Đây là chỗ giữ niềm tin. |

Lý do rất thực dụng: **mỗi lần quay khối 3 tiêu một bounty thật, không lấy lại
được.** Quay một mạch 3 phút mà vấp ở giây 2:55 là mất một bounty và phải làm
lại tất cả.

Thứ duy nhất được phép làm với khối 3 khi dựng là **tua nhanh khúc giữa các
probe không trúng**. Tua nhanh người xem thấy và chấp nhận; cắt rời thì mất tin.

---

## Ngân sách thời gian

Thoại đã đo bằng cách đếm từ, quy đổi ở **150 từ/phút** — nhịp nói tiếng Anh
bình thường, không vội.

| Khối | Khung outline | Thoại đo được | |
|---|---|---|---|
| 1 · câu chuyện | 25s | 27s | thừa 2 |
| 2 · cơ chế | 20s | 22s | thừa 2 |
| 3 · demo | 90s | 65s | **dư 25s** |
| 4 · giá trị biên | 25s | 30s | thừa 5 |
| 5 · giới hạn | 20s | 26s | thừa 6 |
| **tổng** | **180s** | **170s** | còn 10s |

Đọc bảng này thế nào: bốn khối nói đè lên ảnh tĩnh đều hơi tràn, và **khối demo
là chỗ bù**. 25 giây dư ở khối 3 không phải chỗ để nhét thêm lời — đó là khoảng
lặng lúc gõ lệnh, lúc chờ agent chạy, và nhất là nhịp im khi khung
`BOUNTY CLAIMED` hiện ra.

Nếu lượt chạy thật dài hơn 90 giây thì không sao: khúc probe được tua nhanh lúc
dựng.

**Nói nhanh hơn 150 từ/phút để nhét vừa là sai hướng.** Thà cắt khối 2.

---

## Trước khi bấm ghi

### Một lệnh quyết định go / no-go

```bash
./scripts/demo-preflight.sh
```

Nó kiểm: test xanh chưa · còn mấy bounty đòi được · **mọi take có chọn cùng con
số không** · ví agent còn gas không · trang web sống không. Ra `GO` hoặc `NO-GO`.

Chạy nó **ngay trước khi bấm ghi**, không phải từ hôm trước — số bounty đổi mỗi
lần chạy agent.

### Tập dượt trên anvil, đừng tập trên Arc

Cả luồng chạy trên chain cục bộ, miễn phí, không tiêu bounty nào:

```bash
./scripts/compare-strategies.sh
```

Output gần y hệt bản thật (cũng trúng ở probe 6). Dùng nó để canh nhịp lời dẫn.
Chỉ khi thoại đã trơn mới quay take thật lên Arc.

### Dựng màn hình

- Terminal: nền tối, **phóng chữ lên cỡ 18–20pt** (Cmd `+` vài lần). Chữ nhỏ là
  lỗi hay gặp nhất khi quay terminal.
- Cửa sổ terminal **rộng ít nhất 100 cột** — dòng `why:` của giá trị biên dài,
  bị xuống dòng thì rối.
- Tắt notification (Do Not Disturb), ẩn thanh bookmark trình duyệt.
- Ba tab mở sẵn theo thứ tự: **Vercel** · **Arcscan trang Registry** · **GitHub**.
- Ghi ở **1080p trở lên**. Terminal 720p đọc không nổi khi YouTube nén.

---

## Khối 1 · 0:00–0:25 · Vì sao có dự án này

**Hình:** trang issue #123 đã đóng (`~/Downloads/issue#123_closed.jpg` hoặc mở
thẳng GitHub).

**Không gõ gì.** Chỉ nói đè lên ảnh tĩnh.

**Ý cần truyền (tiếng Việt):** kể chuyện thật, không kể tầm nhìn. Hai mươi ngày
đó không phải lỗi của ai, nó chỉ là thời gian chờ người rảnh. Chốt bằng câu hỏi.

**Đọc (English) — 57 từ, ~23 giây:**

> "I was rebuilding Circle's CCTP sample app for Arc, and I found a real bug.
>
> I reported it on the 4th of June. Circle fixed it on the 24th. Twenty days,
> for a thirty-line patch. Nobody did anything wrong. That was just waiting for
> a human to have time.
>
> So: if a bug can be stated as a checkable proposition, why is a human still in
> the middle?"

Trỏ chuột vào dòng `closed as completed in #132` khi nói tới nó.

*27 giây so với khung 25. Thừa 2 giây, bù được ở khối demo. Nếu vẫn cần cắt,
bỏ câu "Nobody did anything wrong."*

---

## Khối 2 · 0:25–0:45 · Cơ chế

**Hình:** slide 6 trong deck (sơ đồ 3 bước), hoặc mục 2 của trang Vercel.

**Ý cần truyền (tiếng Việt):** ba bước trong một giao dịch. Nguyên tử vì hai lý
do: không ai cướp được, và nó chứng minh nhân quả.

**Đọc (English) — 51 từ, ~20 giây:**

> "The agent never calls the target directly. It goes through the Registry, and
> the Registry does three things in **one transaction**. Ask the checker.
> Perform the move. Ask again. Held before, broken now, pay out.
>
> One transaction means no gap to steal the reward. And it pays whoever
> **found** it, not whoever **noticed** it."

*Khối này cắt trước tiên nếu thiếu giờ.*

---

## Khối 3 · 0:45–2:15 · Demo — **một take liền mạch**

Đây là khối duy nhất tiêu tiền thật. Đọc hết trước khi bấm ghi.

### Nhịp 0 — dọn màn hình TRƯỚC khi bấm ghi

`package.json` nằm trong `agent/`, không phải gốc repo. Chạy `npm run attack` ở
gốc là `ENOENT`. Gõ hai lệnh này **trước khi bấm ghi**, không phải trên hình:

```bash
cd /Users/lavopavden/Dev/projects/Proof-of-Break/agent
```

```bash
clear
```

Giờ màn hình sạch và dòng duy nhất sắp hiện là lệnh thật. Bấm ghi, để im khoảng
10 giây rồi mới nói.

**Đọc (English) — 16 từ:**

> "I type one command. From here on, I do not touch the keyboard again."

### Nhịp 1 — gõ lệnh

```bash
npm run attack
```

Gõ chậm cho người xem đọc kịp rồi mới Enter.

### Nhịp 2 — quét sổ (khoảng giây 0–20 của lượt chạy)

Màn hình hiện `SCANNING THE BOARD`, các dòng `✓` và `✗`.

**Ý (tiếng Việt):** nhấn agent chỉ được cho một thứ. Rồi kể nó loại cái gì.

**Đọc (English) — 44 từ, ~18 giây:**

> "It is reading the board off the chain. This agent was told exactly **one
> thing**: the Registry address. Which contracts, which function, what they pay
> — all read at runtime.
>
> And it discards what it cannot win. Already claimed. Rule already broken."

Trỏ vào một dòng `✗` khi nói câu cuối.

### Nhịp 3 — chọn việc

**Đọc (English) — 21 từ, ~8 giây:**

> "It takes the one that pays most. And it names the runner-up, so you can see
> it actually ranked them."

### Nhịp 4 — bắn theo giá trị biên (khúc dài nhất, ~25 giây)

Các dòng `probe 1`, `probe 2`… kèm dòng `why:`.

**Đọc (English) — 38 từ, ~15 giây:**

> "Now it generates input. Not at random. It works a **boundary value list**
> first, and every value carries the reason a tester would try it.
>
> Zero. One. One unit at six decimals. Values you try before knowing anything."

Đọc lướt 2–3 dòng `why:` đầu, đừng đọc hết.

*Khi dựng: đây là khúc được phép tua nhanh.*

### Nhịp 5 — trúng (khoảnh khắc chính của cả video)

Màn hình hiện `BROKE THE INVARIANT` rồi khung `BOUNTY CLAIMED`.

**Im lặng một nhịp cho khung hiện ra.** Đừng nói đè lên.

**Đọc (English) — 31 từ, ~12 giây. Nói chậm, đây là câu quan trọng nhất video.**

> "Probe six. One whole unit at eighteen decimals.
>
> The rule broke. The Registry paid out in that same transaction. The USDC is in
> the agent's own wallet."

Trỏ vào hai dòng số dư trước/sau.

### Nhịp 6 — sang Arcscan (khoảng 20 giây, vẫn cùng take)

Bôi đen tx hash → copy → chuyển tab Arcscan → dán → Enter.

**Đọc (English) — 22 từ, ~9 giây:**

> "That is the hash it just printed. Paste it into the public explorer. Real
> transaction, public chain. Anyone can check it."

Chỉ vào `Success` và địa chỉ ví agent.

**Hết take. Dừng ghi.**

---

## Khối 4 · 2:15–2:40 · Câu ai cũng sẽ hỏi

**Hình:** trang Vercel, cuộn xuống mục 3 (danh sách giá trị biên).

**Ý (tiếng Việt):** nói thẳng câu hỏi ra trước khi giám khảo hỏi. Bằng chứng là
vị trí thứ 6, không phải lời hứa.

**Đọc (English) — 66 từ, ~26 giây:**

> "The question everyone asks: I wrote the target **and** the agent, so how do
> you know it was not told where the bug is?
>
> This is the boundary list, straight from the file the agent reads. It holds
> **no threshold from the target**. `1e18` is on it because that is the most
> common amount in DeFi. Which is exactly why it sits at **six, not one**.
>
> Same agent, pure random: **zero hits in ten thousand.**"

Cuộn chậm qua bảng, dừng ở dòng `1e18` được tô sáng.

*Đừng cắt khối này nếu thiếu giờ. Cắt khối 2 trước.*

---

## Khối 5 · 2:40–3:00 · Giới hạn

**Hình:** mục "Known limitations" trong README, hoặc slide 10.

**Ý (tiếng Việt):** nói giới hạn trước khi bị hỏi. Kết bằng câu định vị.

**Đọc (English) — 63 từ, ~25 giây:**

> "The limits, before anyone asks. This does **not replace an audit**, and it
> does **not protect live TVL**. On a contract holding real money, exploiting
> beats reporting, and nothing here changes that.
>
> What makes it work is **not testnet. It is zero assets at risk.** On mainnet
> the same mechanism runs as a shadow deployment, paying real USDC.
>
> The positioning: continuous QA for the release pipeline."

---

## Sau khi chốt take

- [ ] **Ghi lại tx hash trong video.** Cần cho bước sau.
- [ ] Báo đệ tx hash đó → đệ cập nhật run log trên web sang đúng lần chạy trong
      video, để giám khảo xem video thấy hash nào thì mở web thấy đúng hash đó.
- [ ] Chạy lại `./scripts/demo-preflight.sh` xác nhận trang production đã đổi.
- [ ] Đưa đệ file quay → đệ chèn chú thích và tua nhanh khúc probe.
- [ ] Upload YouTube **unlisted**, mở thử ở cửa sổ ẩn danh.

---

## Nếu take hỏng giữa chừng

**Bounty đã tiêu là mất.** Không có đường hoàn.

Chạy lại pre-flight xem còn mấy cái. Hết thì nạp thêm:

```bash
REGISTRY=0xbBd50574b55CE9F7453882E2d3361b393AD3F99C REWARD_WEI=1500000000000000000 forge script script/OpenBounty.s.sol:OpenBounty --rpc-url "$ARC_RPC_URL" --broadcast --slow --verify --verifier blockscout --verifier-url https://testnet.arcscan.app/api/
```

Giữ nguyên `1500000000000000000` để take mới vẫn hiện cùng con số như take cũ.
