// Dự án đã gắn nhóm lấy lớp của nhóm; dự án chưa gắn nhóm dùng classId lưu trực tiếp.
String resolveProjectClassId(String? groupClassId, String directClassId) =>
    groupClassId?.isNotEmpty == true ? groupClassId! : directClassId;
