 **chức năng chung của app quản lý chi tiêu**

---

### 1. Chức năng chính

* **Đăng nhập**: Sử dụng tài khoản Google.
* **Quản lý giao dịch**: Ghi nhận thu – chi hàng ngày, chọn ngày (mặc định hôm nay), chuyển tiền giữa các nguồn tiền.
* **Nguồn tiền (Account)**: Tạo nhiều nguồn tiền (ví, ngân hàng, tiền mặt, …).
* **Danh mục (Category/Sub-category)**: Tạo danh mục & tiểu mục cho thu nhập và chi tiêu.
* **Tổng hợp báo cáo**:

  * Theo ngày/tuần/tháng/năm/khoảng thời gian tùy chọn.
  * Theo từng danh mục, có thể drill-down xem chi tiết.
  * Hiển thị biểu đồ trực quan (chart, line chart, pie chart).
* **Ngân sách**: Đặt ngân sách tổng hoặc cho từng danh mục, thể hiện % đã chi.
* **Gợi ý nhập liệu**: Gợi ý mô tả từ các mô tả đã nhập trước, gợi ý số tiền theo định dạng.

---

### 2. Chức năng cộng tác (Partner)

* **Kết nối partner**:

  * Tạo mã mời, partner nhập mã để kết nối.
  * Sau khi chấp nhận: cả hai cùng quản lý và chia sẻ dữ liệu.
* **Quyền hiển thị nguồn tiền**: Người dùng chọn ví nào visible hoặc ẩn với partner.
* **Nguồn tiền chung**: Có thể tạo ví chung & ngân sách chung, giao dịch từ ví chung sẽ được cả hai thấy.
* **Tổng hợp**:

  * Thấy được tổng thu/chi cá nhân và tổng hợp với partner.
  * Giao dịch trước khi chấp nhận không bị chia sẻ.

---

### 3. Giao diện & trải nghiệm

* **Thiết kế**: Theme pastel hiện đại (xanh mint chủ đạo).
* **Main screen**:

  * Hiển thị giao dịch gần đây theo nhóm ngày, có “xem tất cả”.
  * Thể hiện tổng thu – tổng chi cá nhân và chung.
* **Report screen**:

  * Trang thu & trang chi riêng.
  * Có lọc thời gian (tuần/tháng/năm).
  * Pie chart + danh sách danh mục theo % và số tiền.
  * Xem chi tiết danh mục với line chart & lịch sử giao dịch.
* **Filter**: Tất cả màn hình đều có bộ lọc thời gian đồng nhất.

---

### 4. Kỹ thuật & vận hành

* **Cơ sở dữ liệu**:

  * Sử dụng **Firebase Realtime Database** để đồng bộ.
  * Có **database local offline** để dùng nhanh, khi có mạng sẽ tự động sync.
* **Xử lý nhập liệu**:

  * Keyboard không che input.
  * Tự động phân cách số tiền bằng dấu `.` khi nhập.

---


Bạn có muốn mình vẽ **sơ đồ tổng quan kiến trúc (modules & flow giữa các màn hình)** để dễ hình dung hơn không?
