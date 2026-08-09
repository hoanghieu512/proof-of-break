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

> "Tôi dựng lại app CCTP mẫu của Circle cho Arc và tìm ra một lỗi thật — một
> trường hợp code không xử lý. Tôi báo ngày 4 tháng 6. Circle sửa ngày 24 tháng
> 6. Hai mươi ngày, cho một bản vá ba mươi dòng.
>
> Không ai làm gì sai cả. Hai mươi ngày đó gần như chỉ để chờ một người có thời
> gian đọc báo cáo và đồng ý.
>
> Nên câu hỏi là: nếu một lỗi diễn đạt được bằng một mệnh đề kiểm chứng được,
> tại sao vẫn cần con người ở giữa?"

Trỏ chuột vào dòng `closed as completed in #132` khi nói tới nó.

---

## Khối 2 · 0:25–0:45 · Cơ chế

**Hình:** slide 6 trong deck (sơ đồ 3 bước), hoặc mục 2 của trang Vercel.

> "Agent không gọi thẳng vào target. Nó gửi hành động qua Registry, và Registry
> làm ba việc trong **một giao dịch**: hỏi checker mệnh đề còn đúng không, thực
> hiện hành động, rồi hỏi lại. Đang đúng mà thành sai thì trả USDC ngay.
>
> Vì sao phải nguyên tử: không có khe hở nào giữa lúc mệnh đề vỡ và lúc tiền
> được trả, nên không ai chen vào cướp được. Và nó chứng minh nhân quả — trả cho
> người **tìm ra**, không trả cho người **nhìn thấy**."

*Khối này cắt trước tiên nếu thiếu giờ.*

---

## Khối 3 · 0:45–2:15 · Demo — **một take liền mạch**

Đây là khối duy nhất tiêu tiền thật. Đọc hết trước khi bấm ghi.

### Nhịp 0 — trước khi gõ (khoảng 10 giây)

Màn hình: terminal trống, đã `cd` sẵn vào `agent/`.

> "Tôi gõ đúng một lệnh. Từ đây tôi không chạm vào bàn phím nữa."

### Nhịp 1 — gõ lệnh

```bash
npm run attack
```

Gõ chậm cho người xem đọc kịp rồi mới Enter.

### Nhịp 2 — quét sổ (khoảng giây 0–20 của lượt chạy)

Màn hình hiện `SCANNING THE BOARD`, các dòng `✓` và `✗`.

> "Nó đang đọc sổ bounty từ chain. Agent được cho **đúng một thứ**: địa chỉ
> Registry. Target là contract nào, hàm nào được phép gọi, thưởng bao nhiêu — nó
> đọc hết lúc chạy, không ai nói trước.
>
> Nó loại những cái không đòi được: cái đã có người đòi, cái mà checker không
> trả lời, cái mà mệnh đề đã hỏng sẵn."

Trỏ vào một dòng `✗` khi nói câu cuối.

### Nhịp 3 — chọn việc

> "Chọn cái trả cao nhất trong số còn khả thi, và nó in luôn cái á quân — nên
> thấy được nó thật sự có xếp hạng, không phải lấy bừa cái đầu tiên."

### Nhịp 4 — bắn theo giá trị biên (khúc dài nhất, ~25 giây)

Các dòng `probe 1`, `probe 2`… kèm dòng `why:`.

> "Giờ nó sinh input. Không phải ngẫu nhiên — nó thử **danh sách giá trị biên**
> trước, và mỗi giá trị đều kèm lý do vì sao một người test sẽ thử giá trị đó.
> Số không. Số một. Một đơn vị ở 6 chữ số thập phân…"

Đọc lướt 2–3 dòng `why:` đầu, đừng đọc hết.

*Khi dựng: đây là khúc được phép tua nhanh.*

### Nhịp 5 — trúng (khoảnh khắc chính của cả video)

Màn hình hiện `BROKE THE INVARIANT` rồi khung `BOUNTY CLAIMED`.

**Im lặng một nhịp cho khung hiện ra.** Đừng nói đè lên.

> "Probe thứ sáu. Một đơn vị nguyên ở 18 chữ số thập phân. Mệnh đề vỡ, Registry
> trả thưởng ngay trong cùng giao dịch đó, và tiền vào ví của chính agent."

Trỏ vào hai dòng số dư trước/sau.

### Nhịp 6 — sang Arcscan (khoảng 20 giây, vẫn cùng take)

Bôi đen tx hash → copy → chuyển tab Arcscan → dán → Enter.

> "Đây là tx hash nó vừa in ra. Dán vào explorer công khai — giao dịch có thật,
> trên chain, ai cũng kiểm được."

Chỉ vào `Success` và địa chỉ ví agent.

**Hết take. Dừng ghi.**

---

## Khối 4 · 2:15–2:40 · Câu ai cũng sẽ hỏi

**Hình:** trang Vercel, cuộn xuống mục 3 (danh sách giá trị biên).

> "Câu hỏi ai cũng sẽ hỏi: tôi viết cả target lẫn agent, sao biết agent không
> được mớm đáp án?
>
> Đây là danh sách giá trị biên, lấy thẳng từ file agent thật sự đọc. Nó **không
> chứa ngưỡng lỗi của target**. `1e18` có mặt vì đó là con số phổ biến nhất của
> DeFi ở 18 chữ số thập phân — và chính vì thế nó nằm ở **vị trí thứ sáu, không
> phải thứ nhất**.
>
> Cùng agent đó, chuyển sang chế độ ngẫu nhiên thuần: **không trúng lần nào
> trong mười nghìn lượt.**"

Cuộn chậm qua bảng, dừng ở dòng `1e18` được tô sáng.

*Đừng cắt khối này nếu thiếu giờ. Cắt khối 2 trước.*

---

## Khối 5 · 2:40–3:00 · Giới hạn

**Hình:** mục "Known limitations" trong README, hoặc slide 10.

> "Nói trước giới hạn. Cái này **không thay thế audit**. Và nó **không bảo vệ
> được TVL đang sống** — trên contract giữ tiền thật, khai thác luôn đáng giá
> hơn nhận thưởng, không cơ chế nào đổi được điều đó.
>
> Thứ làm cơ chế này chạy được **không phải testnet, mà là tài sản bằng không**.
> Trên mainnet nó chạy qua shadow deployment: bản ứng viên lên chain, không nạp
> tài sản nào, bounty trả USDC thật. Bên trong không có gì để lấy, nên nhận
> thưởng là lựa chọn duy nhất có lý.
>
> Định vị của nó: QA liên tục cho đường ống phát hành."

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
