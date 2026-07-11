import { Controller, Post, Body, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation } from '@nestjs/swagger';
import { ApiProperty } from '@nestjs/swagger';
import { IsString, MaxLength, MinLength } from 'class-validator';
import { AuthService } from './auth.service';
import { LoginThrottleGuard } from '../../common/guards/login-throttle.guard';

class LoginDto {
  @ApiProperty({ example: 'STAFF001' })
  @IsString()
  @MinLength(1)
  @MaxLength(20)
  employeeCode: string;

  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  password: string;
}

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private auth: AuthService) {}

  @Post('login')
  @UseGuards(LoginThrottleGuard)
  @ApiOperation({ summary: 'เข้าสู่ระบบ' })
  login(@Body() dto: LoginDto) {
    return this.auth.login(dto.employeeCode, dto.password);
  }
}
