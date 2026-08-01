# Proof-of-Break — Design Doc

**Ngày:** 2026-07-27
**Tác giả:** Hieu Hoang (@lavopavden)
**Sự kiện:** Programmable Money Hackathon (Arc × Circle × Encode) — Track: Agentic Economy
**Deadline final:** 09/08/2026
**Lưu vào repo tại:** `docs/specs/2026-07-27-proof-of-break-design.md`

---

## 1. Bối cảnh xuất phát

Dự án không đến từ ý tưởng trên giấy mà từ một sự việc có thật.

Trong quá trình dựng lại app CCTP mẫu của Circle cho Arc, tôi phát hiện `ensureEvmChain` không xử lý trường hợp ví chưa thêm chain — lỗi ảnh hưởng mọi chain mới, không riêng Arc. Tôi báo issue #123 lên `circlefin/circle-cctp-crosschain-transfer`; Circle sửa trong PR #132.

Vòng lặp đó — tìm ra → viết báo cáo → chờ người đọc → được sửa — mất nhiều tuần và phụ thuộc vào việc có người rảnh. Câu hỏi nảy ra: **nếu một lỗi diễn đạt được bằng mệnh đề kiểm chứng được, tại sao vẫn cần con người ở giữa?**

Nền của tôi là 8+ năm QA. Phần khó của bài toán này không phải Solidity — mà là **định nghĩa invariant đáng kiểm và thiết kế cách kiểm chứng mà máy tin được**. Đó là phần tôi biết làm.

## 2. Sản phẩm là gì

Một sổ bounty on-chain, nơi **agent tự động được trả USDC vì phá được invariant** do người mở bounty tuyên bố, trên contract staging ở Arc Testnet.

Contract tự thẩm định vi phạm và tự trả tiền. Không trọng tài, không báo cáo văn bản, không hàng đợi review.

## 3. Vấn đề giải quyết

**Hiện trạng:** kiểm định bảo mật là sự kiện một lần, đắt (hàng chục nghìn USD), và bị chặn bởi con người. Nền tảng bug bounty vẫn cần người phân loại báo cáo — mất hàng tuần. Dự án nhỏ không đủ tiền. Sau khi audit xong, contract vẫn tiếp tục đổi, không ai phủ tiếp.

**Cái này làm:** biến kiểm định thành **dòng chảy liên tục ở giai đoạn trước khi lên mainnet**, chi phí trả theo kết quả thật thay vì trả trước.

**Cái này KHÔNG làm:** không thay thế audit. Chỉ phủ lớp lỗi diễn đạt được bằng invariant on-chain. Lỗi logic kinh tế, lỗi cần chuỗi nhiều giao dịch — nằm ngoài phạm vi.

## 4. Vì sao là Arc

Mô hình cần **hai điều kiện cùng lúc**:

1. **Gas sub-cent** — fuzz nghĩa là bắn hàng nghìn lần; mỗi lần phải gần như miễn phí.
2. **Gas tính bằng đơn vị ổn định** — chi phí một lần thử và giá trị tiền thưởng không được trôi dạt khỏi nhau giữa chiến dịch. Trên chain có native token biến động, một chiến dịch fuzz có thể từ lãi thành lỗ chỉ vì giá token gấp đôi.

Arc là chain đầu tiên đúng cả hai theo thiết kế (USDC là native gas).

**Hệ quả kỹ thuật:** vì USDC là tiền gốc, bounty nạp và trả thưởng trực tiếp — **không cần bước approve ERC-20 nào**. Trên chain khác phải dựng cả đường ống token.

## 5. Kiến trúc — 4 mảnh

| Mảnh | Vai trò | Ai viết |
|---|---|---|
| **Registry** | Giữ tiền thưởng, giữ danh sách bounty, điều phối và thẩm định | Tôi (hạ tầng) |
| **Checker** | Đọc state công khai của mục tiêu, trả lời invariant còn đúng không | Người mở bounty |
| **Target** | Contract cần kiểm (bản demo: bia tập bắn có lỗi cố ý) | Bất kỳ ai |
| **Agent** | Quét sổ, tự chọn việc, sinh input, bắn, nhận tiền | Bất kỳ ai (bản demo: tôi) |

Registry **không biết và không quan tâm** ai viết Target. Đó là điều cho phép bất kỳ ai mở bounty cho contract của người khác.

## 6. Luồng chạy — nguyên tử trong một giao dịch

Agent **không gọi thẳng** Target. Nó gửi hành động **qua Registry**. Registry làm liền ba việc trong cùng một giao dịch:

1. Hỏi Checker: invariant còn đúng không? → Nếu **đã hỏng sẵn**, dừng, không trả tiền (không chứng minh được nhân quả).
2. Thực hiện hành động lên Target.
3. Hỏi Checker lại → Nếu **vừa đúng giờ sai** → chính hành động này gây ra → trả USDC ngay cho người gọi.

**Vì sao nguyên tử:** không tồn tại khe hở giữa "invariant hỏng" và "nhận thưởng", nên không bot nào chen vào cướp được. Đồng thời chứng minh **quan hệ nhân quả** — trả cho người *tìm ra*, không trả cho người *nhìn thấy*.

## 7. Các quyết định thiết kế đã chốt

### 7.1 Xác minh qua Checker riêng (không để Target tự khai)
Target contract thật ngoài đời không tự khai báo invariant. Checker riêng cho phép hệ thống chạy với **bất kỳ contract nào có state công khai** → có đường tới production. Đây cũng là chỗ kỹ năng QA thể hiện.

### 7.2 Thử-và-nhận-thưởng trong một giao dịch
Xử lý trọn hai vấn đề (cướp thưởng + chứng minh nhân quả) bằng một cơ chế. Đánh đổi: chỉ bắt lỗi **phá được bằng một hành động** — đã nằm trong phạm vi tự giới hạn.

### 7.3 Lỗi ở giá trị biên (boundary value)
Invariant chỉ vỡ ở giá trị đặc biệt (0, 1, max, sát ngưỡng). Fuzz ngẫu nhiên thuần mò rất lâu; agent **thử danh sách biên trước** thì trúng nhanh.
→ Đây là **boundary value analysis**, thứ vỡ lòng của nghề QA. Nó biến "8 năm QA" từ dòng chữ trong deck thành thứ nhìn thấy được trên màn hình.

### 7.4 Một sổ đăng ký chứa nhiều bounty
Agent **tự quét danh sách và tự chọn việc** — đây là ranh giới giữa "agent" và "script được sai bảo", và là thứ track Agentic Economy chấm.

### 7.5 Ba quyết định phụ
- **Thưởng bằng USDC gốc**, không dùng ERC-20 → bỏ hẳn bước approve.
- **Target chỉ ghi sổ nội bộ**, không chuyển tiền thật → tránh việc Registry phải cầm token hộ agent. Invariant: tổng các khoản ghi sổ khớp tổng đã phát hành.
- **Bounty khai luôn chữ ký hàm được phép bắn** (vd `withdraw(uint256)`) → agent đọc chữ ký, biết cần sinh kiểu dữ liệu gì, tự dựng lời gọi mà không cần biết trước Target.

## 8. FAQ / Phản biện

**Liệu tác giả có tự săn thưởng của mình?**
Trong bản demo, tôi đóng cả ba vai: viết Target có lỗi, viết Checker, viết Agent. Đây là **bia tập bắn**, khai công khai, không giấu. Phòng thủ nằm ở kiến trúc: Registry không biết ai viết Target, nên bất kỳ ai cũng mở được bounty cho contract của người khác. Còn tự nhận thưởng của chính mình thì vô nghĩa về kinh tế — lấy lại đúng tiền mình bỏ vào, lỗ tiền gas.
→ **Chủ động nói trước khi bị hỏi.**

**Tính minh bạch?**
Mọi thứ trên chain và đọc được: điều khoản bounty, mã Checker, mã Target, giao dịch nhận thưởng, khoản chi trả. Mã nguồn mở, verify source trên Arcscan. **v1 không có hàm rút tiền** — kể cả tác giả cũng không lấy tiền trong Registry ra được. Không khoá quản trị → không cửa rug.

**Sao không dùng `forge test` / Echidna cho rẻ?**
Đúng, và nên dùng — chúng chạy trong môi trường của *chính đội phát triển*, kiểm những invariant *chính họ nghĩ ra*. Cái này khác ở chỗ: mở invariant cho **bên thứ ba không quen biết** tấn công, có động cơ tiền, chạy liên tục sau khi audit kết thúc. Nó bổ sung fuzzing nội bộ chứ không thay thế.

**Khả thi trên mainnet?**
Điều làm bounty tự động khả thi **không phải testnet — mà là tài sản bằng 0**.

Với contract đang sống giữ tiền thật, khai thác luôn đáng giá hơn báo cáo, trừ khi thưởng lớn hơn cả tài sản bị đe doạ — gần như không bao giờ xảy ra. Hệ thống này **không bảo vệ được TVL đang sống, và tôi không tuyên bố ngược lại.**

Nhưng cùng một cơ chế chạy được trên mainnet thật qua **shadow deployment**: protocol deploy bản ứng viên lên Arc mainnet **không nạp tài sản nào vào** (TVL = 0), rồi treo bounty bằng USDC thật. Agent tấn công thoải mái — phá được cũng chẳng lấy được gì vì bên trong rỗng — nên **nhận thưởng là lựa chọn duy nhất có lý**. Tiền thưởng thật, exploit vô giá trị, và Registry cùng Target vẫn nằm chung một chain nên giữ nguyên tính nguyên tử.

Testnet trong v1 chỉ là bản rẻ nhất của cùng điều kiện đó. Định vị: **QA liên tục cho đường ống phát hành**, không phải lính gác cho TVL.

**Vì sao không đặt bounty ở mainnet còn target ở testnet?**
Vì hai chain khác nhau thì không thể kiểm → thực thi → kiểm lại trong một giao dịch, và toàn bộ cơ chế chống cướp thưởng sụp theo.

**Ý tưởng này có mới không?**
Cơ chế "contract tự thẩm định bằng chứng lỗ hổng và tự trả bounty" được ngành mô tả như một hướng đáng làm nhưng **chưa ai làm được**, vì hai rào cản: ngăn trộm bounty, và thẩm định lỗ hổng bằng máy. Immunefi Vaults mới chỉ làm phần ký quỹ — con người vẫn phán xét.
Đóng góp ở đây: **nhắm vào contract có tài sản bằng 0** (staging testnet ở v1, shadow deployment trên mainnet về sau) làm rào cản 1 tan biến — exploit vô giá trị nên nhận thưởng là lựa chọn duy nhất có lý; và **giới hạn ở lớp lỗi diễn đạt bằng invariant** làm rào cản 2 khả thi.

## 9. Rủi ro kỹ thuật đã biết

| Rủi ro | Mức | Xử lý |
|---|---|---|
| **Reentrancy** — Registry gọi contract lạ với dữ liệu tuỳ ý trong khi đang giữ tiền của mọi bounty | **Cao nhất** | Khoá chống gọi lồng + sổ sách tách bạch từng bounty + kiểm invariant nội bộ: *tổng tiền trong Registry = tổng bounty chưa trả* |
| **RPC rate-limit** — fuzz bắn liên tục, RPC public có thể chặn | Cao | Đo bằng số thật ở Day 1, trước khi build |
| **Số lẻ thập phân USDC gốc trên Arc** | Trung bình | Xác nhận bằng giao dịch thật ở Day 1, không giả định |
| **Target thấy người gọi là Registry, không phải agent** | Đã chấp nhận | Hệ quả tất yếu của cơ chế nguyên tử → hệ thống không dùng cho lỗi phân quyền. Đã chọn lỗi giá trị biên nên không vướng |
| **Người mở bounty rút tiền trước khi agent nhận** | Đã loại | v1 không cho rút, tiền khoá tới khi có người phá được |
| **Lần đầu viết Solidity** | Cao | Kill gate 01/08 (xem §11) |
| **Checker gian** — protocol tự viết Checker luôn trả lời "invariant vẫn đúng" để không bao giờ phải trả thưởng, nhưng vẫn được tiếng là có bounty | Trung bình | Mã Checker công khai và verify được trên Arcscan; agent đọc Checker trước khi bỏ công. v1 chấp nhận rủi ro này và ghi rõ trong giới hạn |
| **Invariant vô nghĩa** — khai một mệnh đề không thể vi phạm (vd "số dư không được âm", trong khi số nguyên không dấu vốn không thể âm) khiến bounty thành đồ trang trí | Trung bình | Invariant phải là mệnh đề **vi phạm được thật**, kiểu sai lệch sổ sách: *tổng số dư ghi nhận cho người dùng luôn khớp lượng token contract đang giữ* |

## 10. Phạm vi v1 — cắt bỏ

### 10.1 v1 làm được gì hôm nay / phần nào là tầm nhìn

Tách rõ hai phần này để không ai phải tự đối chiếu rồi thấy hụt.

| | **v1 — nộp ngày 09/08** | **Tầm nhìn** |
|---|---|---|
| Bounty | Một, do tôi mở | Nhiều, do protocol thật mở |
| Target | Bia tập bắn tôi tự viết, lỗi cố ý | Contract ứng viên thật trước khi lên mainnet |
| Agent | Một, script tất định tôi viết | Nhiều, độc lập, cạnh tranh nhau |
| Tiền thưởng | USDC testnet (không giá trị) | USDC thật, qua shadow deployment TVL = 0 |
| Chứng minh được | **Cơ chế chạy end-to-end, không người can thiệp** | Thị trường hai chiều có thanh khoản |

v1 **không** chứng minh có thị trường. Nó chứng minh **cơ chế hoạt động** — phần mà cho tới nay ngành mới chỉ mô tả chứ chưa ai làm.

### 10.2 Cắt bỏ khỏi v1

**Không làm:** giao diện web, nhiều invariant cho một bounty, lỗi nhiều bước, agent dùng LLM, rút bounty, phân hạng/uy tín agent, chống sybil, chống Checker gian.

Tất cả để sau 06/08 nếu còn thời gian. Demo chạy bằng terminal.

## 11. Lộ trình 13 ngày

| Ngày | Việc | Xong nghĩa là |
|---|---|---|
| 27/7–01/8 | Foundry + deploy được lên Arc + đo RPC/gas | **KILL GATE** |
| 02–05/8 | Registry + Checker + Target + test | Luồng 3 bước chạy trên Arc |
| 06–07/8 | Agent script (TS/viem), chạy end-to-end | Agent tự tìm việc, tự nhận tiền |
| 08/8 | Video 3 phút + deck | Nộp được |
| 09/8 | Đệm, nộp sớm | Final submission |

### Kill gate — 01/08
**Phải deploy được một contract lên Arc Testnet.** Nội dung không quan trọng.
- Được → đi tiếp, còn 8 ngày cho phần lõi.
- Không được → **dừng dự án**, không nộp final. Mất 5 ngày, không mất 13.

Ngưỡng này biến canh bạc 13 ngày thành canh bạc 5 ngày.

## 12. Định nghĩa "xong" cho final submission

- [ ] Registry + Checker + Target deploy trên Arc Testnet, verify source trên Arcscan
- [ ] Agent chạy không người can thiệp: quét sổ → chọn bounty → bắn → nhận USDC
- [ ] Ít nhất một lần phá thành công có tx hash công khai
- [ ] Repo public, README nói rõ phạm vi và giới hạn
- [ ] Video 3 phút quay cảnh agent tìm ra vi phạm và tiền tự về ví
- [ ] Deck

## 13. Câu dùng khi pitch (tiếng Anh)

- *"Autonomous agents get paid in USDC for breaking smart contracts."*
- *"No arbitrator. If a bug can be expressed as an invariant, a machine can judge it — and pay for it."*
- *"What makes automated bounties work isn't testnet. It's zero assets at risk. When there's nothing inside to steal, claiming the bounty is the only rational move."*
- *"On mainnet the same mechanism runs as a shadow deployment: the release candidate goes up with no funds in it, and the bounty is paid in real USDC."*
- *"This doesn't guard live TVL, and I won't claim it does. It's continuous QA for the release pipeline."*
- *"The hard part isn't the Solidity. It's defining invariants worth testing — that's the part I know."*
