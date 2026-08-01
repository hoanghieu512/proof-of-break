# Proof-of-Break — Implementation Plan

**Lưu vào repo tại:** `docs/plans/2026-07-27-proof-of-break-plan.md`
**Design doc:** `docs/specs/2026-07-27-proof-of-break-design.md`
**Deadline final:** 09/08/2026 · **Kill gate:** 01/08/2026

**Goal:** Một agent tự động quét sổ bounty trên Arc, phá được invariant của contract mục tiêu, và tự nhận USDC — không người can thiệp.

**Architecture:** Registry giữ tiền + danh sách bounty và điều phối; Checker trả lời invariant còn đúng không; Target là bia tập bắn có lỗi giá trị biên; Agent là script TS/viem. Cơ chế lõi: kiểm → thực thi → kiểm lại, trọn trong một giao dịch.

**Tech Stack:** Solidity + Foundry (contract, test, fuzz) · TypeScript + viem (agent) · Arc Testnet

**Quy ước:** mỗi Task là một prompt riêng đưa vào Claude Code. Không code trong plan — plan định nghĩa *kết quả mong muốn* và *tiêu chí nghiệm thu*. Commit sau mỗi task.

---

## Cấu trúc file dự kiến

```
proof-of-break/
├── src/
│   ├── BountyRegistry.sol      # giữ tiền, giữ danh sách bounty, điều phối, trả thưởng
│   ├── IChecker.sol            # interface chung cho mọi checker
│   ├── VaultChecker.sol        # checker cho Target demo
│   └── DemoVault.sol           # bia tập bắn, lỗi cố ý ở giá trị biên
├── test/                       # test Foundry, gồm cả invariant test
├── script/                     # script deploy
├── agent/                      # agent TS/viem
└── docs/
    ├── specs/                  # design doc
    └── plans/                  # file này
```

Mỗi file một trách nhiệm. `BountyRegistry.sol` là chỗ duy nhất giữ tiền — mọi thứ liên quan tiền nằm gọn ở đó.

---

## GIAI ĐOẠN 0 — Kill gate (27/07 → 01/08)

### Task 0: Toolchain + deploy được lên Arc

Prompt riêng đã có: `DAY1_PROMPT_foundry-arc-killgate.md`

**Nghiệm thu:**
- [ ] `forge` chạy được
- [ ] Một contract bất kỳ deploy thành công lên Arc Testnet, có địa chỉ + tx hash
- [ ] Biết verify source trên Arcscan được hay không
- [ ] Có số đo: nhịp RPC nào bắt đầu bị chặn
- [ ] Có số đo: gas mỗi giao dịch quy ra USDC
- [ ] Xác nhận số lẻ thập phân của USDC gốc trên Arc bằng giao dịch thật

**KILL GATE:** không đạt trước hết 01/08 → dừng dự án, không nộp final.

---

## GIAI ĐOẠN 1 — Contract lõi (02/08 → 05/08)

### Task 1: Target — bia tập bắn có lỗi giá trị biên

**Files:** tạo `src/DemoVault.sol`, `test/DemoVault.t.sol`

**Kết quả mong muốn:** một contract ghi sổ nội bộ (không chuyển token thật) cho phép nạp/rút theo sổ. Nó **cố ý** chứa một lỗi chỉ lộ ra ở giá trị biên — sổ sách lệch khi gặp giá trị đặc biệt, còn với giá trị thông thường thì luôn đúng.

**Ràng buộc:**
- Lỗi phải nằm ở **giá trị biên**, không phải lỗi phân quyền (xem design doc §7.3).
- Với input thông thường, contract phải hành xử đúng — nếu sai mọi lúc thì demo mất ý nghĩa.
- Lỗi phải phá được bằng **một lời gọi duy nhất**.

**Nghiệm thu:**
- [ ] Test chứng minh: input thông thường → sổ sách khớp
- [ ] Test chứng minh: đúng giá trị biên đó → sổ sách lệch
- [ ] Trong file có ghi chú rõ đây là lỗi cố ý, không phải sơ suất
- [ ] Commit

---

### Task 2: Interface Checker + Checker cho Target

**Files:** tạo `src/IChecker.sol`, `src/VaultChecker.sol`, `test/VaultChecker.t.sol`

**Kết quả mong muốn:** một interface chung mà mọi checker phải tuân theo, chỉ trả lời một câu hỏi: invariant còn đúng không. Kèm một checker cụ thể cho `DemoVault`, kiểm mệnh đề: *tổng các khoản ghi sổ luôn khớp tổng đã phát hành*.

**Ràng buộc:**
- Checker chỉ **đọc**, không đổi state của bất cứ thứ gì.
- Checker không được tin dữ liệu do người gọi truyền vào — chỉ đọc state công khai của Target.
- Invariant phải là mệnh đề **vi phạm được thật** (xem rủi ro "invariant vô nghĩa", design doc §9).

**Nghiệm thu:**
- [ ] Test: trạng thái lành mạnh → checker trả lời "còn đúng"
- [ ] Test: sau khi lỗi biên bị kích hoạt → checker trả lời "đã sai"
- [ ] Checker không có hàm nào ghi state
- [ ] Commit

---

### Task 3: Registry — mở bounty và giữ tiền

**Files:** tạo `src/BountyRegistry.sol`, `test/BountyRegistry.t.sol`

**Kết quả mong muốn:** ai cũng mở được bounty bằng cách khai Target, Checker, hàm được phép bắn, và nạp USDC gốc kèm theo. Danh sách bounty đang mở đọc được công khai. Chưa làm phần tấn công ở task này.

**Ràng buộc:**
- Tiền của từng bounty phải tách bạch — bounty này không đụng được tiền bounty kia.
- **Không có hàm rút tiền** ở v1 (design doc §7, §9).
- Không có khoá quản trị, không ai đặc quyền.

**Nghiệm thu:**
- [ ] Test: mở bounty → tiền vào đúng, đọc lại thông tin khớp
- [ ] Test: mở hai bounty khác nhau → sổ sách hai bên độc lập
- [ ] Test: xác nhận không tồn tại đường rút tiền nào
- [ ] Test: mở bounty mà không nạp tiền → bị từ chối
- [ ] Commit

---

### Task 4: Registry — cơ chế thử-và-nhận-thưởng nguyên tử

**Files:** sửa `src/BountyRegistry.sol`, thêm test vào `test/BountyRegistry.t.sol`

**Kết quả mong muốn:** agent gửi hành động **qua Registry**. Registry làm liền trong một giao dịch: hỏi Checker (đang đúng không) → thực hiện hành động lên Target → hỏi Checker lại. Đang đúng mà thành sai → trả USDC ngay cho người gọi.

**Đây là task nguy hiểm nhất của dự án.** Registry gọi contract lạ với dữ liệu tuỳ ý trong khi đang giữ tiền của mọi bounty.

**Ràng buộc:**
- Phải có khoá chống gọi lồng (reentrancy).
- Nếu invariant **đã hỏng sẵn** trước khi thử → không trả tiền (không chứng minh được nhân quả).
- Chỉ cho bắn đúng hàm mà bounty đã khai, không cho gọi tuỳ ý.
- Một bounty chỉ trả thưởng **một lần**.

**Nghiệm thu:**
- [ ] Test: phá thành công → người gọi nhận đúng số tiền
- [ ] Test: hành động vô hại → không ai nhận được gì
- [ ] Test: invariant hỏng sẵn từ trước → không trả tiền
- [ ] Test: bounty đã trả rồi → không trả lần hai
- [ ] Test: Target độc hại cố gọi ngược vào Registry giữa chừng → **không rút được đồng nào**
- [ ] Test: cố bắn hàm không nằm trong khai báo → bị từ chối
- [ ] Invariant test (Foundry): *tổng tiền trong Registry luôn bằng tổng bounty chưa trả* — chạy qua nhiều chuỗi thao tác ngẫu nhiên
- [ ] Commit

---

### Task 5: Deploy toàn bộ lên Arc Testnet

**Files:** tạo `script/Deploy.s.sol`

**Kết quả mong muốn:** deploy Target, Checker, Registry lên Arc Testnet; mở sẵn một bounty đã nạp tiền; verify source trên Arcscan.

**Nghiệm thu:**
- [ ] Ba contract có địa chỉ trên Arc Testnet
- [ ] Verify source thành công (nếu Task 0 xác nhận làm được)
- [ ] Đọc được bounty đang mở từ ngoài chain
- [ ] Ghi lại toàn bộ địa chỉ vào README
- [ ] Commit

---

## GIAI ĐOẠN 2 — Agent (06/08 → 07/08)

### Task 6: Agent quét sổ và tự chọn việc

**Files:** tạo `agent/` (TS + viem)

**Kết quả mong muốn:** agent đọc danh sách bounty đang mở từ Registry, tự chọn một cái, và hiểu được cần sinh loại dữ liệu gì từ chữ ký hàm mà bounty khai. Chưa tấn công ở task này.

**Ràng buộc:**
- Agent **không được gắn cứng** địa chỉ Target hay tên hàm — phải đọc từ Registry (đây là ranh giới giữa "agent" và "script được sai bảo").
- Dùng ví riêng của agent, tách khỏi ví deployer.

**Nghiệm thu:**
- [ ] Chạy agent → in ra danh sách bounty đang mở đọc từ chain
- [ ] Agent tự xác định được cần sinh kiểu dữ liệu gì
- [ ] Không có địa chỉ Target nào nằm cứng trong code
- [ ] Commit

---

### Task 7: Agent fuzz và nhận thưởng

**Files:** sửa `agent/`

**Kết quả mong muốn:** agent sinh input theo chiến lược **thử giá trị biên trước** rồi mới tới ngẫu nhiên, bắn qua Registry, và khi phá được thì USDC tự về ví nó. Không người can thiệp.

**Ràng buộc:**
- Danh sách giá trị biên phải nằm riêng một chỗ, đọc được — đây là phần thể hiện chuyên môn QA, giám khảo sẽ mở ra xem.
- Nhịp bắn phải nằm dưới ngưỡng RPC đo được ở Task 0.
- Có log rõ ràng đủ để quay video: đang thử gì, kết quả ra sao, lúc nào phá được.

**Nghiệm thu:**
- [ ] Chạy một lệnh duy nhất → agent tự chạy tới lúc nhận được tiền
- [ ] Số dư ví agent tăng đúng bằng tiền thưởng
- [ ] Có tx hash công khai của lần phá thành công
- [ ] Chạy lại lần hai (bounty đã đóng) → agent xử lý gọn, không treo
- [ ] Không bị RPC chặn trong suốt lần chạy
- [ ] Commit

---

## GIAI ĐOẠN 3 — Nộp bài (08/08 → 09/08)

### Task 8: README + video + deck

**Nghiệm thu:**
- [ ] README: cơ chế, địa chỉ contract, cách chạy, **và phần giới hạn nói thẳng** (design doc §10.1)
- [ ] Video 3 phút: quay terminal, agent tìm ra vi phạm và tiền tự về ví
- [ ] Deck: dùng cách kể theo vai Protocol / Platform / Agent / Checker
- [ ] Nêu rõ trong deck: lập luận **tài sản bằng 0** và shadow deployment
- [ ] Commit

### Task 9: Nộp sớm 09/08

- [ ] Repo public, README đầy đủ
- [ ] Link repo + video + deck lên platform
- [ ] Nộp trước hạn ít nhất vài tiếng

---

## Thứ tự ưu tiên khi hụt thời gian

Cắt theo thứ tự này, không cắt lung tung:

1. Bỏ verify source trên Arcscan
2. Bỏ agent chạy nhiều bounty — chỉ cần một
3. Bỏ chiến lược sinh input ngẫu nhiên — chỉ giữ danh sách giá trị biên
4. **Không bao giờ cắt:** khoá chống gọi lồng ở Task 4, và bước kiểm-trước

Nếu tới 07/08 mà agent chưa chạy end-to-end: nộp phần contract + test, khai thẳng agent chưa xong. Nộp bài trung thực còn hơn không nộp.
