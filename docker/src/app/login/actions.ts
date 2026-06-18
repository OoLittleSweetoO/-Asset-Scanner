"use server";

import { redirect } from "next/navigation";
import { signIn } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { hashPassword } from "@/lib/password";

export async function loginAction(formData: FormData) {
  const email = String(formData.get("email") || "");
  const password = String(formData.get("password") || "");
  const result = await signIn(email, password);
  if (!result.ok) {
    redirect(`/login?error=${encodeURIComponent(result.message ?? "Login failed")}`);
  }
  redirect("/app");
}

export async function registerAction(formData: FormData) {
  const name = String(formData.get("name") || "").trim();
  const email = String(formData.get("email") || "").trim().toLowerCase();
  const password = String(formData.get("password") || "");
  const confirmPassword = String(formData.get("confirmPassword") || "");

  if (!name || !email || !password) {
    redirect("/login?error=" + encodeURIComponent("请填写注册信息"));
  }
  if (password.length < 8) {
    redirect("/login?error=" + encodeURIComponent("密码至少 8 位"));
  }
  if (password !== confirmPassword) {
    redirect("/login?error=" + encodeURIComponent("两次输入的密码不一致"));
  }

  const existing = await prisma.user.findUnique({ where: { email } });
  if (existing) {
    redirect("/login?error=" + encodeURIComponent("该邮箱已注册"));
  }

  await prisma.user.create({
    data: {
      name,
      email,
      passwordHash: hashPassword(password),
      role: "USER",
      feishuConfig: { create: {} }
    }
  });

  const result = await signIn(email, password);
  if (!result.ok) redirect("/login?error=" + encodeURIComponent("注册成功，请重新登录"));
  redirect("/app");
}
